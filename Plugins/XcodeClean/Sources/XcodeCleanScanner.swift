import Darwin
import Foundation

typealias XcodeCleanScanProgressHandler = @Sendable (XcodeCleanScanLogMessage) async -> Void

protocol XcodeCleanScanning: Sendable {
    func scan(
        categories: Set<XcodeCleanCategory>,
        progress: XcodeCleanScanProgressHandler
    ) async throws -> XcodeCleanScanResult
}

extension XcodeCleanScanning {
    func scan(categories: Set<XcodeCleanCategory>) async throws -> XcodeCleanScanResult {
        try await scan(categories: categories, progress: { _ in })
    }
}

protocol XcodeCleanFileSystemProviding: Sendable {
    func expandPathPattern(_ pattern: String) throws -> [String]
    func sizeOfItem(at path: String) throws -> Int64
    func itemExists(at path: String) -> Bool
    func removeItem(at path: String) throws
}

struct LocalXcodeCleanFileSystem: XcodeCleanFileSystemProviding, @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String

    init(
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func expandPathPattern(_ pattern: String) throws -> [String] {
        let expanded = expandHome(in: pattern)
        guard Self.containsGlob(expanded) else {
            return itemExists(at: expanded) ? [expanded] : []
        }
        return try Self.globPaths(matching: expanded).sorted()
    }

    func sizeOfItem(at path: String) throws -> Int64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return Int64((attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }

        var total: Int64 = 0
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if values?.isDirectory == true || values?.isSymbolicLink == true {
                continue
            }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    func itemExists(at path: String) -> Bool {
        if fileManager.fileExists(atPath: path) {
            return true
        }
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func removeItem(at path: String) throws {
        guard itemExists(at: path) else { return }
        try fileManager.removeItem(atPath: path)
    }

    private func expandHome(in pattern: String) -> String {
        if pattern == "~" {
            return homeDirectory
        }
        if pattern.hasPrefix("~/") {
            return homeDirectory + String(pattern.dropFirst())
        }
        return pattern
    }

    private static func containsGlob(_ pattern: String) -> Bool {
        pattern.contains { "*?[".contains($0) }
    }

    private static func globPaths(matching pattern: String) throws -> [String] {
        var result = glob_t()
        defer { globfree(&result) }

        let status = pattern.withCString { glob($0, 0, nil, &result) }
        if status == GLOB_NOMATCH {
            return []
        }
        guard status == 0 else {
            throw XcodeCleanFileSystemError.globFailed(pattern: pattern, status: status)
        }
        guard let pathv = result.gl_pathv else { return [] }

        return (0..<Int(result.gl_pathc)).compactMap { index in
            guard let cString = pathv[index] else { return nil }
            return String(cString: cString)
        }
    }
}

enum XcodeCleanFileSystemError: LocalizedError {
    case globFailed(pattern: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case let .globFailed(pattern, status):
            return "无法展开路径 \(pattern)（glob 状态 \(status)）"
        }
    }
}

struct XcodeCleanScanner: XcodeCleanScanning {
    let ruleCatalog: XcodeCleanRuleCatalog
    let fileSystem: XcodeCleanFileSystemProviding
    let allowedRoots: [String]
    let now: @Sendable () -> Date

    init(
        ruleCatalog: XcodeCleanRuleCatalog = .defaultCatalog,
        fileSystem: XcodeCleanFileSystemProviding = LocalXcodeCleanFileSystem(),
        allowedRoots: [String]? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.ruleCatalog = ruleCatalog
        self.fileSystem = fileSystem
        self.allowedRoots = (allowedRoots ?? Self.defaultAllowedRoots()).map { Self.ensureTrailingSlash($0) }
        self.now = now
    }

    func scan(
        categories: Set<XcodeCleanCategory>,
        progress: XcodeCleanScanProgressHandler
    ) async throws -> XcodeCleanScanResult {
        var candidates: [XcodeCleanCandidate] = []

        for category in XcodeCleanCategory.allCases where categories.contains(category) {
            try Task.checkCancellation()

            await progress(
                XcodeCleanScanLogMessage(
                    text: "扫描分类：\(category.title)",
                    tone: .info
                )
            )

            for rule in ruleCatalog.rules(for: category) {
                try Task.checkCancellation()

                for pattern in rule.pathPatterns {
                    try Task.checkCancellation()
                    let matches = (try? fileSystem.expandPathPattern(pattern)) ?? []
                    await progress(
                        XcodeCleanScanLogMessage(
                            text: "展开 \(pattern) → \(matches.count) 项",
                            tone: matches.isEmpty ? .info : .success
                        )
                    )

                    for path in matches {
                        try Task.checkCancellation()
                        let safety = safetyStatus(for: path)
                        let size = safety.isCleanable ? ((try? fileSystem.sizeOfItem(at: path)) ?? 0) : 0
                        let candidate = XcodeCleanCandidate(
                            id: "\(rule.id)::\(path)",
                            category: category,
                            path: path,
                            sizeBytes: size,
                            safety: safety
                        )
                        candidates.append(candidate)
                        await progress(logMessage(for: candidate))
                    }
                }
            }
        }

        let cleanable = candidates.filter { $0.safety.isCleanable }
        await progress(
            XcodeCleanScanLogMessage(
                text: "扫描完成：\(candidates.count) 项，\(cleanable.count) 项可清理",
                tone: .success
            )
        )

        return XcodeCleanScanResult(
            categories: categories,
            candidates: candidates,
            scannedAt: now()
        )
    }

    private func safetyStatus(for path: String) -> XcodeCleanSafetyStatus {
        if !fileSystem.itemExists(at: path) {
            return .missing
        }
        if !isPathAllowed(path) {
            return .outsideAllowedRoot
        }
        return .allowed
    }

    private func isPathAllowed(_ path: String) -> Bool {
        let normalized = path.hasSuffix("/") ? path : path
        return allowedRoots.contains { normalized.hasPrefix($0) }
    }

    private func logMessage(for candidate: XcodeCleanCandidate) -> XcodeCleanScanLogMessage {
        switch candidate.safety {
        case .allowed:
            return XcodeCleanScanLogMessage(text: "可清理：\(candidate.path)", tone: .success)
        case .outsideAllowedRoot:
            return XcodeCleanScanLogMessage(text: "越界拒绝：\(candidate.path)", tone: .warning)
        case .xcodeRunning:
            return XcodeCleanScanLogMessage(text: "Xcode 运行中：\(candidate.path)", tone: .warning)
        case .missing:
            return XcodeCleanScanLogMessage(text: "已不存在：\(candidate.path)", tone: .info)
        }
    }

    private static func defaultAllowedRoots() -> [String] {
        let home = NSHomeDirectory()
        return XcodeCleanRuleCatalog.allowedRootPrefixes.map { prefix in
            prefix.hasPrefix("~/") ? home + String(prefix.dropFirst()) : prefix
        }
    }

    private static func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
