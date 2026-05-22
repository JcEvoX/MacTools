import Foundation

// MARK: - ZshConfigFileType

/// zsh 配置文件类型枚举，涵盖用户家目录下所有标准 zsh 配置文件。
enum ZshConfigFileType: String, CaseIterable, Identifiable, Codable {
    case zshrc    = ".zshrc"
    case zshenv   = ".zshenv"
    case zprofile = ".zprofile"
    case zlogin   = ".zlogin"
    case zlogout  = ".zlogout"

    var id: String { rawValue }
    var filename: String { rawValue }

    /// 文件用途说明（一句话）
    var role: String {
        switch self {
        case .zshrc:    return "交互式 Shell 配置：别名、函数、提示符等"
        case .zshenv:   return "所有 Shell 的环境变量，最先被加载"
        case .zprofile: return "登录 Shell 初始化，早于 .zshrc"
        case .zlogin:   return "登录 Shell 完成初始化后执行"
        case .zlogout:  return "退出登录 Shell 时执行的清理脚本"
        }
    }

    /// 加载时机说明
    var whenLoaded: String {
        switch self {
        case .zshrc:    return "每次打开新终端窗口/标签页时"
        case .zshenv:   return "每次启动 zsh（包括脚本、非交互式）时"
        case .zprofile: return "登录时（SSH、macOS 登录等），早于 .zshrc"
        case .zlogin:   return "登录时，晚于 .zshrc"
        case .zlogout:  return "登录 Shell 退出时（`exit` 或关闭终端）"
        }
    }

    /// 推荐用途提示
    var recommendedUse: String {
        switch self {
        case .zshrc:    return "alias、函数、主题（Oh My Zsh / Starship 等）、PATH"
        case .zshenv:   return "EDITOR、LANG、必须对所有子进程可见的变量"
        case .zprofile: return "Homebrew 的环境初始化、一次性登录脚本"
        case .zlogin:   return "欢迎信息、tmux 自动启动等"
        case .zlogout:  return "清理临时文件、记录会话日志"
        }
    }

    /// 文件的绝对 URL（用户家目录下）
    var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(rawValue)
    }
}

// MARK: - ZshFileStatus

/// 某个 zsh 配置文件的当前状态快照。
struct ZshFileStatus {
    let type: ZshConfigFileType
    let exists: Bool
    let isWritable: Bool
    let byteSize: Int
    let modifiedDate: Date?

    /// 格式化文件大小字符串
    var formattedSize: String {
        guard exists else { return "" }
        if byteSize < 1024 { return "\(byteSize) B" }
        return String(format: "%.1f KB", Double(byteSize) / 1024)
    }

    /// 通过 FileManager 探测文件实际状态
    static func probe(_ type: ZshConfigFileType) -> ZshFileStatus {
        let url = type.fileURL
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        let isWritable: Bool
        if exists {
            isWritable = fm.isWritableFile(atPath: url.path)
        } else {
            // 文件不存在时检查父目录是否可写（能否创建）
            isWritable = fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
        }
        var byteSize = 0
        var modifiedDate: Date? = nil
        if exists,
           let attrs = try? fm.attributesOfItem(atPath: url.path) {
            byteSize = (attrs[.size] as? Int) ?? 0
            modifiedDate = attrs[.modificationDate] as? Date
        }
        return ZshFileStatus(
            type: type,
            exists: exists,
            isWritable: isWritable,
            byteSize: byteSize,
            modifiedDate: modifiedDate
        )
    }
}

// MARK: - ZshSnippet

/// 快速插入片段模板。
struct ZshSnippet: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let description: String
    /// 输入框占位文字提示
    let placeholder: String
    /// 根据用户输入生成待插入的文本
    let buildContent: @Sendable (String) -> String

    static let all: [ZshSnippet] = [
        ZshSnippet(
            id: "alias",
            icon: "arrow.uturn.right",
            title: "别名",
            description: "为命令创建快捷方式",
            placeholder: "名称=命令，例：gs=git status",
            buildContent: { input in
                let trimmed = input.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return "alias \(parts[0].trimmingCharacters(in: .whitespaces))='\(parts[1].trimmingCharacters(in: .whitespaces))'"
                }
                return "alias \(trimmed)=''"
            }
        ),
        ZshSnippet(
            id: "export",
            icon: "square.and.arrow.up",
            title: "环境变量",
            description: "设置或覆盖环境变量",
            placeholder: "变量名=值，例：EDITOR=nvim",
            buildContent: { input in
                let trimmed = input.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    return "export \(parts[0].trimmingCharacters(in: .whitespaces))=\(parts[1].trimmingCharacters(in: .whitespaces))"
                }
                return "export \(trimmed)="
            }
        ),
        ZshSnippet(
            id: "path",
            icon: "folder.badge.plus",
            title: "PATH 路径",
            description: "将目录追加到 $PATH",
            placeholder: "目录路径，例：/opt/homebrew/bin",
            buildContent: { input in
                let path = input.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { return "export PATH=\"$PATH:/your/path\"" }
                return "export PATH=\"$PATH:\(path)\""
            }
        ),
        ZshSnippet(
            id: "source",
            icon: "doc.badge.plus",
            title: "加载文件",
            description: "在当前 Shell 中执行另一个脚本",
            placeholder: "文件路径，例：~/.config/secrets.sh",
            buildContent: { input in
                let path = input.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { return "source ~/.your-script.sh" }
                return "source \(path)"
            }
        ),
        ZshSnippet(
            id: "function",
            icon: "f.cursive",
            title: "函数",
            description: "定义一个可复用的 Shell 函数",
            placeholder: "函数名称，例：mkcd",
            buildContent: { input in
                let name = input.trimmingCharacters(in: .whitespaces)
                let funcName = name.isEmpty ? "my_func" : name
                return "\(funcName)() {\n  # 在此填写函数内容\n  \n}"
            }
        ),
        ZshSnippet(
            id: "eval",
            icon: "terminal",
            title: "初始化工具",
            description: "执行工具的 eval 初始化命令",
            placeholder: "工具命令，例：$(brew shellenv)",
            buildContent: { input in
                let cmd = input.trimmingCharacters(in: .whitespaces)
                guard !cmd.isEmpty else { return "eval \"$(your-tool init zsh)\"" }
                // 如果输入已包含 $(...) 或 backtick，直接用 eval
                if cmd.hasPrefix("$(") || cmd.hasPrefix("`") {
                    return "eval \"\(cmd)\""
                }
                return "eval \"$(\(cmd))\""
            }
        ),
    ]
}
