import AppKit
import SwiftUI

// MARK: - ZshSyntaxHighlightingEditor

/// NSTextView-based code editor with zsh/shell syntax highlighting.
/// Supports comments, keywords, quoted strings, and variable references.
struct ZshSyntaxHighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    /// Called whenever the user edits the content (not on programmatic updates).
    var onChange: (() -> Void)? = nil
    /// Increment to trigger a one-shot scroll to the bottom of the document.
    var scrollToBottomID: Int = 0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.typingAttributes = Self.baseAttributes

        if !text.isEmpty {
            textView.string = text
            Self.applyHighlighting(to: textView)
        }
        // 记录初始内容，updateNSView 依靠此判断是否需要外部重置
        context.coordinator.lastTextFedToBinding = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        guard !context.coordinator.isHighlighting else { return }

        // 只有当外部（加载文件、追加片段）真正改变了 text 时才重置 textView.string。
        // 不能用 textView.string != text 判断：@Published 在 willSet（赋值前）发出
        // objectWillChange，updateNSView 可能拿到旧值而误触发重置，从而清空 undo 栈。
        if text != context.coordinator.lastTextFedToBinding {
            context.coordinator.lastTextFedToBinding = text
            let sel = textView.selectedRange()
            textView.string = text
            Self.applyHighlighting(to: textView)
            let safeLocation = min(sel.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }
        textView.isEditable = isEditable
        if scrollToBottomID != context.coordinator.lastScrollToBottomID {
            context.coordinator.lastScrollToBottomID = scrollToBottomID
            textView.scrollToEndOfDocument(nil)
        }
    }

    // MARK: - Syntax Definitions

    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ]

    private static let syntaxRules: [(NSRegularExpression, NSColor)] = {
        let defs: [(String, NSColor)] = [
            // Double-quoted strings
            (#""[^"\\]*(?:\\.[^"\\]*)*""#,           .systemOrange),
            // Single-quoted strings
            (#"'[^']*'"#,                             .systemOrange),
            // Variable references: $VAR or ${VAR}
            (#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#,    .systemTeal),
            // zsh/shell keywords and builtins
            (
                #"\b(alias|export|source|function|eval|if|then|else|elif|fi|for|in|do|done|while|until|case|esac|return|local|readonly|unset|typeset|setopt|unsetopt|autoload|bindkey|compinit|zle)\b"#,
                .systemBlue
            ),
        ]
        return defs.compactMap { pattern, color in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, color) }
        }
    }()

    private static let commentRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"#.*$"#, options: .anchorsMatchLines)

    static func applyHighlighting(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let string = textView.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)

        // 语法高亮属性变化不应进入 undo 栈，否则 Cmd+Z 会撤销高亮而非文字内容
        let undoManager = textView.undoManager
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }

        storage.beginEditing()

        // Reset to base style
        storage.setAttributes(baseAttributes, range: fullRange)

        // Apply keyword / string / variable coloring
        for (regex, color) in syntaxRules {
            regex.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
                guard let r = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }

        // Comments override all other rules (applied last)
        commentRegex?.enumerateMatches(in: string, options: [], range: fullRange) { match, _, _ in
            guard let r = match?.range else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
        }

        storage.endEditing()

        // Keep typing attributes consistent so new characters start with base style
        textView.typingAttributes = baseAttributes
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ZshSyntaxHighlightingEditor
        var isHighlighting = false
        var lastScrollToBottomID: Int = 0
        /// 上一次由 textDidChange 推送给 binding 的文本，用于区分用户输入与外部赋值
        var lastTextFedToBinding: String = ""

        init(_ parent: ZshSyntaxHighlightingEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView = notification.object as? NSTextView else { return }
            lastTextFedToBinding = textView.string
            parent.text = textView.string
            parent.onChange?()
            isHighlighting = true
            ZshSyntaxHighlightingEditor.applyHighlighting(to: textView)
            isHighlighting = false
        }
    }
}
