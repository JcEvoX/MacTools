import AppKit
import Foundation
import OSLog

@MainActor
final class RightClickURLRouter {
    static let shared = RightClickURLRouter()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "RightClickURLRouter"
    )
    private var fileActionService = RightClickFileActionService()

    private init() {}

    func handle(_ urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    func handle(_ url: URL) {
        guard url.scheme == "mactools", url.host == "right-click" else {
            return
        }

        switch url.path {
        case "/new-folder":
            handleNewFolder(url)
        default:
            logger.error("Unsupported right-click URL path: \(url.path, privacy: .public)")
        }
    }

    private func handleNewFolder(_ url: URL) {
        guard let directoryPath = queryValue("directory", in: url), !directoryPath.isEmpty else {
            logger.error("Missing directory for new-folder URL")
            return
        }

        do {
            let folderURL = try fileActionService.createFolder(in: URL(fileURLWithPath: directoryPath))
            logger.info("Created folder at \(folderURL.path, privacy: .public)")
        } catch {
            logger.error("Create folder failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        queryValues(name, in: url).first
    }

    private func queryValues(_ name: String, in url: URL) -> [String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .filter { $0.name == name }
            .compactMap(\.value) ?? []
    }
}
