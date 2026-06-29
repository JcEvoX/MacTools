import AppKit
import Foundation

enum RightClickActionError: LocalizedError, Equatable {
    case directoryUnavailable(String)
    case cannotCreateDirectory(String)
    case cannotCreateFile(String)
    case unsupportedFileExtension(String)
    case applicationUnavailable(String)
    case noValidFiles

    var errorDescription: String? {
        switch self {
        case let .directoryUnavailable(path):
            "文件夹不可用：\(path)"
        case let .cannotCreateDirectory(path):
            "无法新建文件夹：\(path)"
        case let .cannotCreateFile(path):
            "无法新建文件：\(path)"
        case let .unsupportedFileExtension(ext):
            "不支持的文件类型：\(ext)"
        case let .applicationUnavailable(path):
            "应用不可用：\(path)"
        case .noValidFiles:
            "没有可用的文件"
        }
    }
}

struct RightClickPathFormatter {
    static func relativePath(of target: URL, to base: URL) -> String {
        let baseComponents = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let targetComponents = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var sharedCount = 0

        while sharedCount < baseComponents.count,
              sharedCount < targetComponents.count,
              baseComponents[sharedCount] == targetComponents[sharedCount] {
            sharedCount += 1
        }

        let upCount = max(0, baseComponents.count - sharedCount)
        let downComponents = targetComponents.dropFirst(sharedCount)
        let components = Array(repeating: "..", count: upCount) + Array(downComponents)
        return components.isEmpty ? "." : components.joined(separator: "/")
    }

    static func joinedPaths(_ urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    static func joinedFileNames(_ urls: [URL]) -> String {
        urls.map(\.lastPathComponent).joined(separator: "\n")
    }

    static func joinedRelativePaths(_ urls: [URL], base: URL?) -> String {
        urls
            .map { url in
                guard let base else {
                    return url.path
                }

                return relativePath(of: url, to: base)
            }
            .joined(separator: "\n")
    }

    /// Shell-escaped paths, space-separated so the whole line can be pasted as
    /// terminal arguments.
    static func joinedShellEscapedPaths(_ urls: [URL]) -> String {
        urls.map { shellEscaped($0.path) }.joined(separator: " ")
    }

    static func joinedFileURLs(_ urls: [URL]) -> String {
        urls.map(\.absoluteString).joined(separator: "\n")
    }

    /// Single-quote wrap, with embedded single quotes escaped as `'\''`.
    static func shellEscaped(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct RightClickTargetResolver {
    static func targetDirectory(selectedURLs: [URL], targetedURL: URL?) -> URL? {
        if let first = selectedURLs.first {
            return directory(for: first)
        }

        if let targetedURL {
            return directory(for: targetedURL)
        }

        return nil
    }

    static func directory(for url: URL) -> URL {
        if isDirectory(url) {
            return url
        }

        return url.deletingLastPathComponent()
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

struct RightClickFileNamePlanner {
    static func nextAvailableFolderURL(in directory: URL, baseName: String = "新建文件夹") -> URL {
        nextAvailableURL(in: directory, baseName: baseName, pathExtension: nil)
    }

    static func nextAvailableURL(in directory: URL, baseName: String, pathExtension: String?) -> URL {
        let sanitizedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名"
            : baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExtension = pathExtension?.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        func candidate(_ index: Int?) -> URL {
            let name: String
            if let index {
                name = "\(sanitizedBaseName) \(index)"
            } else {
                name = sanitizedBaseName
            }

            let url = directory.appendingPathComponent(name, isDirectory: normalizedExtension == nil)
            guard let normalizedExtension, !normalizedExtension.isEmpty else {
                return url
            }

            return url.appendingPathExtension(normalizedExtension)
        }

        let manager = FileManager.default
        var url = candidate(nil)
        guard manager.fileExists(atPath: url.path) else {
            return url
        }

        var index = 2
        repeat {
            url = candidate(index)
            index += 1
        } while manager.fileExists(atPath: url.path)

        return url
    }
}

protocol RightClickWorkspaceOpening {
    func activateFileViewerSelecting(_ urls: [URL])
}

struct RightClickWorkspace: RightClickWorkspaceOpening {
    func activateFileViewerSelecting(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct RightClickFileActionService {
    var fileManager: FileManager = .default
    var workspace: RightClickWorkspaceOpening = RightClickWorkspace()

    func createFolder(in directory: URL) throws -> URL {
        guard RightClickTargetResolver.isDirectory(directory) else {
            throw RightClickActionError.directoryUnavailable(directory.path)
        }

        let folderURL = RightClickFileNamePlanner.nextAvailableFolderURL(in: directory)
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
            workspace.activateFileViewerSelecting([folderURL])
            return folderURL
        } catch {
            throw RightClickActionError.cannotCreateDirectory(folderURL.path)
        }
    }

    /// Create an empty file of an allow-listed type inside the target directory,
    /// then reveal it in Finder. The extension allow list also blocks path
    /// traversal through the forwarded `ext` parameter.
    func createFile(in directory: URL, extension fileExtension: String) throws -> URL {
        guard RightClickNewFile.isSupportedExtension(fileExtension) else {
            throw RightClickActionError.unsupportedFileExtension(fileExtension)
        }
        guard RightClickTargetResolver.isDirectory(directory) else {
            throw RightClickActionError.directoryUnavailable(directory.path)
        }
        let fileURL = RightClickFileNamePlanner.nextAvailableURL(
            in: directory,
            baseName: "未命名",
            pathExtension: fileExtension
        )
        // Defense-in-depth: the resolved file must sit directly inside the target.
        guard fileURL.deletingLastPathComponent().standardizedFileURL.path
            == directory.standardizedFileURL.path else {
            throw RightClickActionError.cannotCreateFile(fileURL.path)
        }
        guard fileManager.createFile(atPath: fileURL.path, contents: Data(), attributes: nil) else {
            throw RightClickActionError.cannotCreateFile(fileURL.path)
        }
        workspace.activateFileViewerSelecting([fileURL])
        return fileURL
    }
}

/// New-file types the right-click menu may create. A strict allow list keeps the
/// feature to its intended types and — because the host's URL scheme can be
/// invoked by any process — prevents path traversal through the `ext` parameter.
enum RightClickNewFile {
    static let supportedExtensions: [String] = ["txt", "md", "json"]

    static func isSupportedExtension(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }
}
