import AppKit
import XCTest
@testable import MacTools

final class RightClickPathFormatterTests: XCTestCase {
    func testRelativePathWithinBaseDirectory() {
        let base = URL(fileURLWithPath: "/Users/test/Projects")
        let target = URL(fileURLWithPath: "/Users/test/Projects/MacTools/README.md")

        XCTAssertEqual(
            RightClickPathFormatter.relativePath(of: target, to: base),
            "MacTools/README.md"
        )
    }

    func testRelativePathForSiblingDirectory() {
        let base = URL(fileURLWithPath: "/Users/test/Projects/MacTools")
        let target = URL(fileURLWithPath: "/Users/test/Desktop/note.txt")

        XCTAssertEqual(
            RightClickPathFormatter.relativePath(of: target, to: base),
            "../../Desktop/note.txt"
        )
    }

    func testJoinedRelativePathsFallsBackToAbsolutePathWithoutBase() {
        let target = URL(fileURLWithPath: "/Users/test/Desktop/note.txt")

        XCTAssertEqual(
            RightClickPathFormatter.joinedRelativePaths([target], base: nil),
            "/Users/test/Desktop/note.txt"
        )
    }
}

final class RightClickFileNamePlannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testNextAvailableFolderUsesDefaultNameWhenAvailable() throws {
        let url = RightClickFileNamePlanner.nextAvailableFolderURL(in: temporaryDirectory)

        XCTAssertEqual(url.lastPathComponent, "新建文件夹")
    }

    func testNextAvailableFolderSkipsExistingNames() throws {
        try FileManager.default.createDirectory(
            at: temporaryDirectory.appendingPathComponent("新建文件夹", isDirectory: true),
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory.appendingPathComponent("新建文件夹 2", isDirectory: true),
            withIntermediateDirectories: false
        )

        let url = RightClickFileNamePlanner.nextAvailableFolderURL(in: temporaryDirectory)

        XCTAssertEqual(url.lastPathComponent, "新建文件夹 3")
    }

    func testCreateFolderCreatesAndSelectsNewFolder() throws {
        let workspace = RightClickWorkspaceSpy()
        let service = RightClickFileActionService(workspace: workspace)

        let createdURL = try service.createFolder(in: temporaryDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))
        XCTAssertEqual(workspace.selectedURLs, [createdURL])
    }
}

private final class RightClickWorkspaceSpy: RightClickWorkspaceOpening {
    var selectedURLs: [URL] = []

    func activateFileViewerSelecting(_ urls: [URL]) {
        selectedURLs = urls
    }
}
