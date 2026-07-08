import AppKit

enum SyntaxHighlighter {
    private enum Language {
        case cLike
        case css
        case html
        case json
        case markdown
        case plain
        case python
        case shell
        case swift
        case yaml
    }

    static func attributedString(for text: String,
                                 fileName: String?,
                                 font: NSFont,
                                 lineHeight: CGFloat) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes(font: font,
                                                                                            lineHeight: lineHeight))
        switch language(for: fileName) {
            case .cLike:
                applyCodeColors(to: attributed, text: text)
            case .css:
                applyCSSColors(to: attributed, text: text)
            case .html:
                applyHTMLColors(to: attributed, text: text)
            case .json:
                applyJSONColors(to: attributed, text: text)
            case .markdown:
                applyMarkdownColors(to: attributed, text: text)
            case .python:
                applyPythonColors(to: attributed, text: text)
            case .shell:
                applyShellColors(to: attributed, text: text)
            case .swift:
                applySwiftColors(to: attributed, text: text)
            case .yaml:
                applyYAMLColors(to: attributed, text: text)
            case .plain:
                break
        }
        return attributed
    }

    private static func baseAttributes(font: NSFont, lineHeight: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping
        return [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
    }

    private static func language(for fileName: String?) -> Language {
        guard let fileName, !fileName.isEmpty else { return .plain }
        let lower = fileName.lowercased()
        let name = URL(fileURLWithPath: lower).lastPathComponent
        let ext = URL(fileURLWithPath: lower).pathExtension

        if ["md", "markdown", "mdown"].contains(ext) { return .markdown }
        if ["swift"].contains(ext) { return .swift }
        if ["py", "pyw"].contains(ext) { return .python }
        if ["c", "cc", "cpp", "cxx", "h", "hh", "hpp", "hxx", "m", "mm", "java", "kt", "kts", "go", "rs", "cs", "php", "rb", "js", "jsx", "ts", "tsx"].contains(ext) {
            return .cLike
        }
        if ["json", "jsonc"].contains(ext) { return .json }
        if ["yml", "yaml"].contains(ext) { return .yaml }
        if ["sh", "bash", "zsh", "fish"].contains(ext) || name == "makefile" { return .shell }
        if ["html", "htm", "xml", "xhtml", "plist"].contains(ext) { return .html }
        if ["css", "scss", "sass", "less"].contains(ext) { return .css }
        return .plain
    }

    private static func applyCodeColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"\b\d+(?:\.\d+)?\b"#, color: .systemOrange, to: attributed, text: text)
        apply(pattern: #"\b(?:alignas|alignof|auto|bool|break|case|catch|char|class|concept|const|constexpr|continue|decltype|default|delete|do|double|else|enum|explicit|extern|false|float|for|friend|if|import|inline|int|long|namespace|new|null|nullptr|operator|private|protected|public|return|short|signed|sizeof|static|struct|switch|template|this|throw|true|try|typedef|typename|union|unsigned|using|virtual|void|volatile|while|let|var|function|interface|type|extends|implements|package|from|export|await|async|yield)\b"#,
              color: .systemPurple,
              to: attributed,
              text: text)
        apply(pattern: #"(?m)^\s*#\s*\w+.*$"#, color: .systemBlue, to: attributed, text: text)
        applyCStyleComments(to: attributed, text: text)
    }

    private static func applySwiftColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"\b\d+(?:\.\d+)?\b"#, color: .systemOrange, to: attributed, text: text)
        apply(pattern: #"\b(?:actor|any|as|associatedtype|async|await|break|case|catch|class|continue|default|defer|do|else|enum|extension|false|for|func|guard|if|import|in|init|inout|is|let|nil|nonisolated|operator|private|protocol|public|rethrows|return|self|some|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#,
              color: .systemPurple,
              to: attributed,
              text: text)
        applyCStyleComments(to: attributed, text: text)
    }

    private static func applyPythonColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"\b\d+(?:\.\d+)?\b"#, color: .systemOrange, to: attributed, text: text)
        apply(pattern: #"\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#,
              color: .systemPurple,
              to: attributed,
              text: text)
        apply(pattern: #"(?m)#.*$"#, color: .systemGreen, to: attributed, text: text)
    }

    private static func applyShellColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"\b(?:case|do|done|elif|else|esac|export|fi|for|function|if|in|local|readonly|return|select|then|until|while)\b"#,
              color: .systemPurple,
              to: attributed,
              text: text)
        apply(pattern: #"\$\{?[_A-Za-z][_A-Za-z0-9]*\}?"#, color: .systemTeal, to: attributed, text: text)
        apply(pattern: #"(?m)#.*$"#, color: .systemGreen, to: attributed, text: text)
    }

    private static func applyMarkdownColors(to attributed: NSMutableAttributedString, text: String) {
        apply(pattern: #"(?m)^#{1,6}\s.*$"#, color: .systemBlue, to: attributed, text: text)
        apply(pattern: #"(?m)^\s*>\s.*$"#, color: .systemGreen, to: attributed, text: text)
        apply(pattern: #"(?m)^\s*(?:[-*+]\s|\d+\.\s).*$"#, color: .systemOrange, to: attributed, text: text)
        apply(pattern: #"`[^`\n]+`"#, color: .systemRed, to: attributed, text: text)
        apply(pattern: #"(?m)^```.*$"#, color: .systemRed, to: attributed, text: text)
        apply(pattern: #"\[[^\]]+\]\([^)]+\)"#, color: .systemBlue, to: attributed, text: text)
    }

    private static func applyJSONColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #""(?:\\.|[^"\\])*"(?=\s*:)"#, color: .systemBlue, to: attributed, text: text)
        apply(pattern: #"\b(?:true|false|null)\b"#, color: .systemPurple, to: attributed, text: text)
        apply(pattern: #"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: .systemOrange, to: attributed, text: text)
    }

    private static func applyYAMLColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"(?m)^\s*[-]?\s*[^#\n:]+(?=:)"#, color: .systemBlue, to: attributed, text: text)
        apply(pattern: #"\b(?:true|false|null|yes|no|on|off)\b"#,
              color: .systemPurple,
              to: attributed,
              text: text,
              options: [.caseInsensitive])
        apply(pattern: #"\b-?\d+(?:\.\d+)?\b"#, color: .systemOrange, to: attributed, text: text)
        apply(pattern: #"(?m)#.*$"#, color: .systemGreen, to: attributed, text: text)
    }

    private static func applyHTMLColors(to attributed: NSMutableAttributedString, text: String) {
        apply(pattern: #"<!--[\s\S]*?-->"#, color: .systemGreen, to: attributed, text: text)
        apply(pattern: #"</?[A-Za-z][^>]*>"#, color: .systemBlue, to: attributed, text: text)
        applyStrings(to: attributed, text: text)
    }

    private static func applyCSSColors(to attributed: NSMutableAttributedString, text: String) {
        applyStrings(to: attributed, text: text)
        apply(pattern: #"/\*[\s\S]*?\*/"#, color: .systemGreen, to: attributed, text: text)
        apply(pattern: #"(?m)^[^{\n]+(?=\s*\{)"#, color: .systemBlue, to: attributed, text: text)
        apply(pattern: #"\b[-A-Za-z]+\b(?=\s*:)"#, color: .systemTeal, to: attributed, text: text)
        apply(pattern: #"#[0-9A-Fa-f]{3,8}\b"#, color: .systemOrange, to: attributed, text: text)
    }

    private static func applyStrings(to attributed: NSMutableAttributedString, text: String) {
        apply(pattern: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: .systemRed, to: attributed, text: text)
    }

    private static func applyCStyleComments(to attributed: NSMutableAttributedString, text: String) {
        apply(pattern: #"//.*$"#, color: .systemGreen, to: attributed, text: text, options: [.anchorsMatchLines])
        apply(pattern: #"/\*[\s\S]*?\*/"#, color: .systemGreen, to: attributed, text: text)
    }

    private static func apply(pattern: String,
                              color: NSColor,
                              to attributed: NSMutableAttributedString,
                              text: String,
                              options: NSRegularExpression.Options = []) {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        for match in regex.matches(in: text, options: [], range: range) {
            guard match.range.location != NSNotFound, match.range.length > 0 else { continue }
            attributed.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
