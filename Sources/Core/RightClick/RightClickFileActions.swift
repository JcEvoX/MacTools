import AppKit
import Foundation

enum RightClickActionError: LocalizedError, Equatable {
    case directoryUnavailable(String)
    case cannotCreateDirectory(String)

    var errorDescription: String? {
        switch self {
        case let .directoryUnavailable(path):
            "文件夹不可用：\(path)"
        case let .cannotCreateDirectory(path):
            "无法新建文件夹：\(path)"
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
}
