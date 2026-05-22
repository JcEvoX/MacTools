import XCTest
@testable import ZshConfigPlugin

// MARK: - ZshConfigFileType Tests

final class ZshConfigFileTypeTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(ZshConfigFileType.allCases.count, 5)
    }

    func testFilenameMatchesRawValue() {
        for type in ZshConfigFileType.allCases {
            XCTAssertEqual(type.filename, type.rawValue)
        }
    }

    func testIdMatchesRawValue() {
        for type in ZshConfigFileType.allCases {
            XCTAssertEqual(type.id, type.rawValue)
        }
    }

    func testFileURLIsUnderHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for type in ZshConfigFileType.allCases {
            XCTAssertTrue(type.fileURL.path.hasPrefix(home), "\(type.filename) URL should be under home")
        }
    }

    func testFileURLLastComponentMatchesFilename() {
        for type in ZshConfigFileType.allCases {
            XCTAssertEqual(type.fileURL.lastPathComponent, type.filename)
        }
    }

    func testEachTypeHasNonEmptyRole() {
        for type in ZshConfigFileType.allCases {
            XCTAssertFalse(type.role.isEmpty, "\(type.filename) role should not be empty")
        }
    }

    func testEachTypeHasNonEmptyWhenLoaded() {
        for type in ZshConfigFileType.allCases {
            XCTAssertFalse(type.whenLoaded.isEmpty, "\(type.filename) whenLoaded should not be empty")
        }
    }

    func testEachTypeHasNonEmptyRecommendedUse() {
        for type in ZshConfigFileType.allCases {
            XCTAssertFalse(type.recommendedUse.isEmpty, "\(type.filename) recommendedUse should not be empty")
        }
    }

    func testCodableRoundtrip() throws {
        for type in ZshConfigFileType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(ZshConfigFileType.self, from: data)
            XCTAssertEqual(decoded, type)
        }
    }
}

// MARK: - ZshFileStatus Tests

final class ZshFileStatusTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZshFileStatusTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testNonExistentFileHasEmptyFormattedSize() {
        let status = ZshFileStatus(
            type: .zshrc,
            exists: false,
            isWritable: true,
            byteSize: 0,
            modifiedDate: nil
        )
        XCTAssertFalse(status.exists)
        XCTAssertEqual(status.formattedSize, "")
    }

    func testExistingFileHasNonEmptyFormattedSize() {
        let status = ZshFileStatus(
            type: .zshrc,
            exists: true,
            isWritable: true,
            byteSize: 512,
            modifiedDate: Date()
        )
        XCTAssertTrue(status.exists)
        XCTAssertFalse(status.formattedSize.isEmpty)
    }

    func testFormattedSizeZeroBytes() {
        let status = ZshFileStatus(type: .zshrc, exists: true, isWritable: true, byteSize: 0, modifiedDate: nil)
        XCTAssertEqual(status.formattedSize, "0 B")
    }

    func testFormattedSizeBelowKiloByte() {
        let status = ZshFileStatus(type: .zshrc, exists: true, isWritable: true, byteSize: 500, modifiedDate: nil)
        XCTAssertTrue(status.formattedSize.hasSuffix("B"),
                      "500 bytes should display as B, got '\(status.formattedSize)'")
    }

    func testFormattedSizeExactly1024IsKB() {
        let status = ZshFileStatus(type: .zshrc, exists: true, isWritable: true, byteSize: 1024, modifiedDate: nil)
        XCTAssertTrue(status.formattedSize.hasSuffix("KB"),
                      "1024 bytes should display as KB, got '\(status.formattedSize)'")
    }

    func testFormattedSizeAboveKiloByte() {
        let status = ZshFileStatus(type: .zshrc, exists: true, isWritable: true, byteSize: 2048, modifiedDate: nil)
        XCTAssertTrue(status.formattedSize.hasSuffix("KB"),
                      "2048 bytes should display as KB, got '\(status.formattedSize)'")
    }
}

// MARK: - ZshSnippet Tests

final class ZshSnippetTests: XCTestCase {

    func testAllSnippetsCount() {
        XCTAssertGreaterThanOrEqual(ZshSnippet.all.count, 5)
    }

    func testAllSnippetsHaveUniqueIDs() {
        let ids = ZshSnippet.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAllSnippetsHaveNonEmptyTitle() {
        for snippet in ZshSnippet.all {
            XCTAssertFalse(snippet.title.isEmpty, "Snippet '\(snippet.id)' should have a title")
        }
    }

    func testAllSnippetsHaveNonEmptyIcon() {
        for snippet in ZshSnippet.all {
            XCTAssertFalse(snippet.icon.isEmpty, "Snippet '\(snippet.id)' should have an icon")
        }
    }

    func testAllSnippetsHaveNonEmptyPlaceholder() {
        for snippet in ZshSnippet.all {
            XCTAssertFalse(snippet.placeholder.isEmpty, "Snippet '\(snippet.id)' should have a placeholder")
        }
    }

    func testAllSnippetsProduceNonEmptyOutput() {
        for snippet in ZshSnippet.all {
            let result = snippet.buildContent("test_input")
            XCTAssertFalse(result.isEmpty, "Snippet '\(snippet.id)' produced empty output for non-empty input")
        }
    }

    // MARK: alias

    func testAliasSnippetWithEqualsInput() {
        let snippet = ZshSnippet.all.first { $0.id == "alias" }!
        let result = snippet.buildContent("gs=git status")
        XCTAssertEqual(result, "alias gs='git status'")
    }

    func testAliasSnippetWithoutEqualsProducesEmptyValue() {
        let snippet = ZshSnippet.all.first { $0.id == "alias" }!
        let result = snippet.buildContent("myalias")
        XCTAssertTrue(result.hasPrefix("alias myalias"))
        XCTAssertTrue(result.hasSuffix("''"))
    }

    // MARK: export

    func testExportSnippetWithEqualsInput() {
        let snippet = ZshSnippet.all.first { $0.id == "export" }!
        let result = snippet.buildContent("EDITOR=nvim")
        XCTAssertEqual(result, "export EDITOR=nvim")
    }

    func testExportSnippetWithoutEqualsProducesEmptyValue() {
        let snippet = ZshSnippet.all.first { $0.id == "export" }!
        let result = snippet.buildContent("MYVAR")
        XCTAssertTrue(result.hasPrefix("export MYVAR"))
        XCTAssertTrue(result.hasSuffix("="))
    }

    // MARK: path

    func testPathSnippetContainsPATH() {
        let snippet = ZshSnippet.all.first { $0.id == "path" }!
        let result = snippet.buildContent("/opt/homebrew/bin")
        XCTAssertTrue(result.contains("$PATH"))
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
    }

    func testPathSnippetEmptyInputUsesPlaceholderPath() {
        let snippet = ZshSnippet.all.first { $0.id == "path" }!
        let result = snippet.buildContent("")
        XCTAssertTrue(result.contains("$PATH"))
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: source

    func testSourceSnippet() {
        let snippet = ZshSnippet.all.first { $0.id == "source" }!
        let result = snippet.buildContent("~/.config/secrets.sh")
        XCTAssertEqual(result, "source ~/.config/secrets.sh")
    }

    func testSourceSnippetEmptyInputUsesPlaceholder() {
        let snippet = ZshSnippet.all.first { $0.id == "source" }!
        let result = snippet.buildContent("")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.hasPrefix("source "))
    }

    // MARK: function

    func testFunctionSnippetUsesInputAsName() {
        let snippet = ZshSnippet.all.first { $0.id == "function" }!
        let result = snippet.buildContent("mkcd")
        XCTAssertTrue(result.hasPrefix("mkcd()"))
        XCTAssertTrue(result.contains("{"))
        XCTAssertTrue(result.contains("}"))
    }

    func testFunctionSnippetEmptyInputUsesDefaultName() {
        let snippet = ZshSnippet.all.first { $0.id == "function" }!
        let result = snippet.buildContent("")
        // 空名称时使用 "my_func" 作为默认函数名
        XCTAssertTrue(result.hasPrefix("my_func()"))
        XCTAssertTrue(result.contains("{"))
        XCTAssertTrue(result.contains("}"))
    }

    // MARK: eval

    func testEvalSnippetWithSubshellInputWrapsDirectly() {
        let snippet = ZshSnippet.all.first { $0.id == "eval" }!
        let result = snippet.buildContent("$(brew shellenv)")
        XCTAssertTrue(result.hasPrefix("eval"))
        XCTAssertTrue(result.contains("$(brew shellenv)"))
    }

    func testEvalSnippetWithPlainInputWrapsInSubshell() {
        let snippet = ZshSnippet.all.first { $0.id == "eval" }!
        let result = snippet.buildContent("rbenv init -")
        XCTAssertTrue(result.hasPrefix("eval"))
        XCTAssertTrue(result.contains("rbenv init -"))
    }

    func testEvalSnippetEmptyInputUsesPlaceholder() {
        let snippet = ZshSnippet.all.first { $0.id == "eval" }!
        let result = snippet.buildContent("")
        XCTAssertTrue(result.hasPrefix("eval"))
        XCTAssertFalse(result.isEmpty)
    }
}

// MARK: - ZshConfigStore Tests

@MainActor
final class ZshConfigStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZshConfigStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: Store Initialization

    func testDefaultSelectedTypeIsZshrc() {
        let store = ZshConfigStore()
        XCTAssertEqual(store.selectedType, .zshrc)
    }

    func testInitialUnsavedChangesIsFalse() {
        let store = ZshConfigStore()
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testInitialSaveErrorIsNil() {
        let store = ZshConfigStore()
        XCTAssertNil(store.saveError)
    }

    func testInitialIsBusyIsFalse() {
        let store = ZshConfigStore()
        XCTAssertFalse(store.isBusy)
    }

    func testInitialLastSaveSucceededIsFalse() {
        let store = ZshConfigStore()
        XCTAssertFalse(store.lastSaveSucceeded)
    }

    // MARK: Select

    func testSelectDifferentTypeSwitchesType() {
        let store = ZshConfigStore()
        store.select(.zshenv)
        XCTAssertEqual(store.selectedType, .zshenv)
    }

    func testSelectSameTypeIsNoOp() {
        let store = ZshConfigStore()
        // selectedType is already .zshrc; calling select with the same value should be a no-op
        store.select(.zshrc)
        XCTAssertEqual(store.selectedType, .zshrc)
    }

    func testSelectResetsUnsavedChanges() {
        let store = ZshConfigStore()
        // 制造未保存改动
        store.editingContent = store.editingContent + "\n# test change"
        store.markEdited()
        XCTAssertTrue(store.hasUnsavedChanges)
        // 切换到其他文件后应重置
        store.select(.zshenv)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testSelectClearsSaveError() {
        let store = ZshConfigStore()
        store.select(.zshenv)
        XCTAssertNil(store.saveError)
    }

    // MARK: appendSnippet

    func testAppendSnippetToEmptyContent() {
        let store = ZshConfigStore()
        store.editingContent = ""
        store.appendSnippet("alias gs='git status'")
        XCTAssertEqual(store.editingContent, "alias gs='git status'")
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testAppendSnippetToNonEmptyContentAddsNewlineSeparator() {
        // 内容末尾无换行时，追加 \n\n + text
        let store = ZshConfigStore()
        store.editingContent = "# existing content"
        store.appendSnippet("alias gs='git status'")
        XCTAssertTrue(store.editingContent.contains("\nalias gs='git status'"))
    }

    func testAppendSnippetWithSingleTrailingNewlineAddsOneExtraNewline() {
        // 内容末尾恰好有一个 \n，追加 \n + text（共两个 \n 作为空行分隔）
        let store = ZshConfigStore()
        store.editingContent = "# existing\n"
        store.appendSnippet("alias gs='git status'")
        // 结果应包含空行分隔（\n\n），但不应出现三个连续换行
        XCTAssertTrue(store.editingContent.contains("\n\nalias gs='git status'"))
        XCTAssertFalse(store.editingContent.contains("\n\n\nalias gs='git status'"))
    }

    func testAppendSnippetWithDoubleTrailingNewlineAppendsDirectly() {
        // 内容末尾已有 \n\n，直接追加，不再增加额外换行
        let store = ZshConfigStore()
        store.editingContent = "# existing\n\n"
        store.appendSnippet("alias gs='git status'")
        XCTAssertTrue(store.editingContent.hasSuffix("\n\nalias gs='git status'"))
        XCTAssertFalse(store.editingContent.contains("\n\n\nalias gs='git status'"))
    }

    func testAppendSnippetSetsUnsavedChanges() {
        let store = ZshConfigStore()
        XCTAssertFalse(store.hasUnsavedChanges)
        store.appendSnippet("test")
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    // MARK: markEdited

    func testMarkEditedSetsUnsavedChangesWhenContentModified() {
        let store = ZshConfigStore()
        // 在已加载内容基础上追加修改，使 editingContent 与 savedContent 不同
        store.editingContent = store.editingContent + "\n# test modification"
        store.markEdited()
        XCTAssertTrue(store.hasUnsavedChanges)
    }

    func testMarkEditedKeepsUnsavedChangesFalseWhenContentUnchanged() {
        let store = ZshConfigStore()
        // 未修改内容，markEdited 应识别出内容未变，不标记为有未保存改动
        store.markEdited()
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testMarkEditedClearsLastSaveSucceeded() {
        let store = ZshConfigStore()
        store.markEdited()
        XCTAssertFalse(store.lastSaveSucceeded)
    }

    // MARK: refreshStatusMap

    func testRefreshStatusMapPopulatesAllTypes() {
        let store = ZshConfigStore()
        store.refreshStatusMap()
        for type in ZshConfigFileType.allCases {
            XCTAssertNotNil(store.statusMap[type], "statusMap should contain entry for \(type.filename)")
        }
    }

    func testStatusMapIsPopulatedAfterInit() {
        let store = ZshConfigStore()
        // refreshStatusMap 在 init 中被调用，不需要手动触发
        XCTAssertEqual(store.statusMap.count, ZshConfigFileType.allCases.count)
    }
}
