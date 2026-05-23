import Foundation
import MacToolsPluginKit

struct PluginPackageManifest: Codable, Equatable {
    struct Capabilities: Codable, Equatable {
        let primaryPanel: Bool
        let componentPanel: Bool
        let configuration: Bool

        init(primaryPanel: Bool = false, componentPanel: Bool = false, configuration: Bool = false) {
            self.primaryPanel = primaryPanel
            self.componentPanel = componentPanel
            self.configuration = configuration
        }
    }

    let id: String
    let displayName: String
    let version: String
    let minHostVersion: String
    let pluginKitVersion: Int
    let bundleRelativePath: String
    let factoryClass: String?
    let capabilities: Capabilities
    let permissions: [String]

    init(
        id: String,
        displayName: String,
        version: String,
        minHostVersion: String,
        pluginKitVersion: Int = PluginPackageManifestLoader.supportedPluginKitVersion,
        bundleRelativePath: String,
        factoryClass: String? = nil,
        capabilities: Capabilities = Capabilities(),
        permissions: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.minHostVersion = minHostVersion
        self.pluginKitVersion = pluginKitVersion
        self.bundleRelativePath = bundleRelativePath
        self.factoryClass = factoryClass
        self.capabilities = capabilities
        self.permissions = permissions
    }
}

enum PluginPackageManifestError: LocalizedError, Equatable {
    case missingManifest(URL)
    case unreadableManifest(URL)
    case invalidIdentifier(String)
    case invalidVersion(String)
    case invalidBundleRelativePath(String)
    case unsupportedPluginKitVersion(Int)
    case incompatibleHostVersion(required: String, current: String)

    var errorDescription: String? {
        switch self {
        case let .missingManifest(url):
            return "插件缺少 manifest：\(url.path)"
        case let .unreadableManifest(url):
            return "插件 manifest 无法读取：\(url.path)"
        case let .invalidIdentifier(id):
            return "插件 ID 不合法：\(id)"
        case let .invalidVersion(version):
            return "插件版本号不合法：\(version)"
        case let .invalidBundleRelativePath(path):
            return "插件入口路径不合法：\(path)"
        case let .unsupportedPluginKitVersion(version):
            return "插件 SDK 版本不支持：\(version)"
        case let .incompatibleHostVersion(required, current):
            return "插件需要 MacTools \(required) 或更高版本，当前版本为 \(current)。"
        }
    }
}

enum PluginPackageManifestLoader {
    static let fileName = "plugin.json"
    static let supportedPluginKitVersion = PluginKitCompatibility.currentVersion

    static func load(
        from packageURL: URL,
        hostVersion: String = AppMetadata.shortVersion ?? "0"
    ) throws -> PluginPackageManifest {
        let manifest = try readManifest(from: packageURL)
        try validate(manifest, hostVersion: hostVersion)
        return manifest
    }

    static func decode(from packageURL: URL) throws -> PluginPackageManifest {
        try readManifest(from: packageURL)
    }

    static func validate(_ manifest: PluginPackageManifest, hostVersion: String) throws {
        try validatePackageIdentity(manifest)

        guard manifest.pluginKitVersion == supportedPluginKitVersion else {
            throw PluginPackageManifestError.unsupportedPluginKitVersion(manifest.pluginKitVersion)
        }

        guard PluginVersionComparator.isVersion(hostVersion, atLeast: manifest.minHostVersion) else {
            throw PluginPackageManifestError.incompatibleHostVersion(
                required: manifest.minHostVersion,
                current: hostVersion
            )
        }
    }

    static func validatePackageIdentity(_ manifest: PluginPackageManifest) throws {
        guard isValidPluginID(manifest.id) else {
            throw PluginPackageManifestError.invalidIdentifier(manifest.id)
        }

        guard isValidVersion(manifest.version) else {
            throw PluginPackageManifestError.invalidVersion(manifest.version)
        }

        guard isValidVersion(manifest.minHostVersion) else {
            throw PluginPackageManifestError.invalidVersion(manifest.minHostVersion)
        }

        guard
            !manifest.bundleRelativePath.isEmpty,
            !manifest.bundleRelativePath.hasPrefix("/"),
            !manifest.bundleRelativePath.split(separator: "/").contains("..")
        else {
            throw PluginPackageManifestError.invalidBundleRelativePath(manifest.bundleRelativePath)
        }
    }

    private static func isValidPluginID(_ id: String) -> Bool {
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9._-]{1,126}[A-Za-z0-9]$"#
        return id.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidVersion(_ version: String) -> Bool {
        let pattern = #"^[0-9]+(?:\.[0-9]+){0,2}$"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }

    private static func readManifest(from packageURL: URL) throws -> PluginPackageManifest {
        let manifestURL = packageURL.appendingPathComponent(fileName, isDirectory: false)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginPackageManifestError.missingManifest(manifestURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw PluginPackageManifestError.unreadableManifest(manifestURL)
        }

        do {
            return try JSONDecoder().decode(PluginPackageManifest.self, from: data)
        } catch {
            throw PluginPackageManifestError.unreadableManifest(manifestURL)
        }
    }

}
