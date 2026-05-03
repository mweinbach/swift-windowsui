import SwiftWindowsCore
import SwiftWindowsLayout
import SwiftWindowsUI

public struct GeometryProxy {
    public let size: Size

    public init(size: Size) {
        self.size = size
    }
}

extension SwiftWindowsCore.Color: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Color has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(backgroundColor: self, isHitTestVisible: false)
        }
    }
}

@MainActor
public struct Group: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Group has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: content, context: context)
    }
}

@MainActor
public struct ForEach<Data: RandomAccessCollection, ID: Hashable>: View {
    public typealias Body = Never

    let expandedContent: [AnyView]

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: (Data.Element) -> [AnyView]) {
        self.expandedContent = data.enumerated().flatMap { _, element in
            let elementID = String(describing: element[keyPath: id])
            return content(element).enumerated().map { childOffset, view in
                AnyView(view.id("\(elementID):\(childOffset)"))
            }
        }
    }

    public init(_ data: Data, @ViewBuilder content: (Data.Element) -> [AnyView]) where Data.Element: Identifiable, ID == Data.Element.ID {
        self.init(data, id: \.id, content: content)
    }

    public init(_ data: Range<Int>, @ViewBuilder content: (Int) -> [AnyView]) where Data == Range<Int>, ID == Int {
        self.init(data, id: \.self, content: content)
    }

    public init(_ data: ClosedRange<Int>, @ViewBuilder content: (Int) -> [AnyView]) where Data == ClosedRange<Int>, ID == Int {
        self.init(data, id: \.self, content: content)
    }

    public var body: Never {
        fatalError("ForEach has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: expandedContent,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}

public extension ViewBuilder {
    static func buildExpression<Data: RandomAccessCollection, ID: Hashable>(
        _ expression: ForEach<Data, ID>
    ) -> [AnyView] {
        expression.expandedContent
    }
}

@MainActor
public struct Text: View {
    public typealias Body = Never

    public enum Case: Sendable, Equatable {
        case uppercase
        case lowercase
    }

    public enum TruncationMode: Sendable, Equatable {
        case head
        case tail
        case middle
    }

    private var content: String
    private var color: Color
    private var font: Font
    private var alignment: TextAlignment
    private var lineLimit: Int?
    private var truncationMode: TruncationMode
    private var letterSpacing: Double
    private var lineSpacing: Double
    private var isItalic: Bool
    private var underline: Bool
    private var strikethrough: Bool
    private var enableKerning: Bool
    private var spans: [TextSpan]?

    public init(_ content: String) {
        self.content = content
        self.color = .white
        self.font = .system(size: 2)
        self.alignment = .center
        self.lineLimit = nil
        self.truncationMode = .tail
        self.letterSpacing = 1
        self.lineSpacing = 2
        self.isItalic = false
        self.underline = false
        self.strikethrough = false
        self.enableKerning = true
        self.spans = nil
    }

    public init<S: StringProtocol>(_ content: S) {
        self.init(String(content))
    }

    public init(verbatim content: String) {
        self.init(content)
    }

    public var body: Never {
        fatalError("Text has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.label(
                content,
                color: color,
                scale: font.resolvedScale,
                weight: font.weight.textWeight,
                fontFamily: font.resolvedFamily,
                alignment: alignment.horizontalAlignment.textAlignment,
                letterSpacing: letterSpacing,
                lineSpacing: lineSpacing,
                lineBreakMode: resolvedLineBreakMode,
                maximumNumberOfLines: lineLimit,
                italic: isItalic,
                underline: underline,
                strikethrough: strikethrough,
                enableKerning: enableKerning,
                spans: spans
            )
        }
    }

    public func foregroundColor(_ color: Color?) -> Text {
        guard let color else {
            return self
        }

        var copy = self
        copy.color = color
        copy.updateSpanStyles { style in
            style.color = color
        }
        return copy
    }

    public func foregroundStyle(_ color: Color?) -> Text {
        foregroundColor(color)
    }

    public func font(_ font: Font?) -> Text {
        guard let font else {
            return self
        }

        var copy = self
        copy.font = font
        copy.updateSpanStyles { style in
            style.scale = font.resolvedScale
            style.weight = font.weight.textWeight
            style.fontFamily = font.resolvedFamily
        }
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        copy.updateSpanStyles { style in
            style.alignment = alignment.horizontalAlignment.textAlignment
        }
        return copy
    }

    public func lineLimit(_ lineLimit: Int?) -> Text {
        var copy = self
        copy.lineLimit = lineLimit
        let lineBreakMode = copy.resolvedLineBreakMode
        copy.updateSpanStyles { style in
            style.maximumNumberOfLines = lineLimit
            style.lineBreakMode = lineBreakMode
        }
        return copy
    }

    public func truncationMode(_ mode: Text.TruncationMode) -> Text {
        var copy = self
        copy.truncationMode = mode
        let lineBreakMode = copy.resolvedLineBreakMode
        copy.updateSpanStyles { style in
            style.lineBreakMode = lineBreakMode
        }
        return copy
    }

    public func kerning(_ value: CGFloat) -> Text {
        var copy = self
        copy.letterSpacing = value
        copy.updateSpanStyles { style in
            style.letterSpacing = value
        }
        return copy
    }

    public func tracking(_ value: CGFloat) -> Text {
        kerning(value)
    }

    public func lineSpacing(_ value: CGFloat) -> Text {
        var copy = self
        copy.lineSpacing = value
        copy.updateSpanStyles { style in
            style.lineSpacing = value
        }
        return copy
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        guard let weight else {
            return self
        }

        var copy = self
        copy.font.weight = weight
        copy.updateSpanStyles { style in
            style.weight = weight.textWeight
        }
        return copy
    }

    public func fontDesign(_ design: Font.Design?) -> Text {
        guard let design else {
            return self
        }

        var copy = self
        copy.font.design = design
        copy.font.family = nil
        let family = copy.font.resolvedFamily
        copy.updateSpanStyles { style in
            style.fontFamily = family
        }
        return copy
    }

    public func bold() -> Text {
        fontWeight(.bold)
    }

    public func italic() -> Text {
        var copy = self
        copy.isItalic = true
        copy.updateSpanStyles { style in
            style.italic = true
        }
        return copy
    }

    public func monospaced() -> Text {
        var copy = self
        copy.font.family = "Cascadia Mono"
        copy.updateSpanStyles { style in
            style.fontFamily = "Cascadia Mono"
        }
        return copy
    }

    public func underline(_ active: Bool = true) -> Text {
        var copy = self
        copy.underline = active
        copy.updateSpanStyles { style in
            style.underline = active
        }
        return copy
    }

    public func strikethrough(_ active: Bool = true) -> Text {
        var copy = self
        copy.strikethrough = active
        copy.updateSpanStyles { style in
            style.strikethrough = active
        }
        return copy
    }

    public func textCase(_ textCase: Text.Case?) -> Text {
        guard let textCase else {
            return self
        }

        var copy = self
        copy.applyTextCase(textCase)
        return copy
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        let content = lhs.content + rhs.content
        var combined = Text(content)
        combined.color = lhs.color
        combined.font = lhs.font
        combined.alignment = lhs.alignment
        combined.lineLimit = lhs.lineLimit ?? rhs.lineLimit
        combined.truncationMode = lhs.truncationMode
        combined.letterSpacing = lhs.letterSpacing
        combined.lineSpacing = lhs.lineSpacing
        combined.isItalic = lhs.isItalic
        combined.underline = lhs.underline
        combined.strikethrough = lhs.strikethrough
        combined.enableKerning = lhs.enableKerning
        combined.spans = spans(for: lhs.segments + rhs.segments, in: content)
        return combined
    }

    private var resolvedLineBreakMode: TextLineBreakMode {
        if let lineLimit, lineLimit == 1 {
            return truncationMode.lineBreakMode
        }

        return .wrap
    }

    fileprivate var promptContent: String {
        content
    }

    private struct Segment {
        var text: String
        var style: PixelTextStyle
    }

    private var segments: [Segment] {
        if let spans, !spans.isEmpty {
            return spans.map { Segment(text: $0.text, style: $0.style) }
        }

        return [Segment(text: content, style: segmentStyle)]
    }

    private var segmentStyle: PixelTextStyle {
        PixelTextStyle(
            color: color,
            scale: font.resolvedScale,
            alignment: alignment.horizontalAlignment.textAlignment,
            letterSpacing: letterSpacing,
            lineSpacing: lineSpacing,
            fontFamily: font.resolvedFamily,
            weight: font.weight.textWeight,
            lineBreakMode: resolvedLineBreakMode,
            maximumNumberOfLines: lineLimit,
            italic: isItalic,
            underline: underline,
            strikethrough: strikethrough,
            enableKerning: enableKerning
        )
    }

    private mutating func updateSpanStyles(_ update: (inout PixelTextStyle) -> Void) {
        guard var spans else {
            return
        }

        for index in spans.indices {
            update(&spans[index].style)
        }
        self.spans = spans
    }

    private mutating func applyTextCase(_ textCase: Text.Case) {
        guard spans != nil else {
            content = transformedText(content, textCase: textCase)
            return
        }

        let transformedSegments = segments.map { segment in
            Segment(text: transformedText(segment.text, textCase: textCase), style: segment.style)
        }
        content = transformedSegments.map(\.text).joined()
        spans = Self.spans(for: transformedSegments, in: content)
    }

    private static func spans(for segments: [Segment], in content: String) -> [TextSpan] {
        var cursor = content.startIndex
        var spans: [TextSpan] = []
        spans.reserveCapacity(segments.count)

        for segment in segments {
            guard !segment.text.isEmpty else {
                continue
            }
            let nextCursor = content.index(cursor, offsetBy: segment.text.count)
            spans.append(TextSpan(text: segment.text, style: segment.style, range: cursor..<nextCursor))
            cursor = nextCursor
        }

        return spans
    }
}

@MainActor
public struct Image: View {
    public typealias Body = Never

    private let systemName: String
    private var color: Color
    private var font: Font
    private var alignment: TextAlignment

    public init(systemName: String) {
        self.systemName = systemName
        self.color = .white
        self.font = .system(size: 1.9)
        self.alignment = .center
    }

    public var body: Never {
        fatalError("Image has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let symbol = resolvedSymbolIcon(for: systemName)
        return Component { _ in
            Controls.icon(
                symbol,
                color: color,
                scale: font.resolvedScale,
                alignment: alignment.horizontalAlignment.textAlignment
            )
        }
    }

    public func foregroundColor(_ color: Color?) -> Image {
        guard let color else {
            return self
        }

        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color?) -> Image {
        foregroundColor(color)
    }

    public func font(_ font: Font?) -> Image {
        guard let font else {
            return self
        }

        var copy = self
        copy.font = font
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Image {
        var copy = self
        copy.alignment = alignment
        return copy
    }
}

@MainActor
public struct Label: View {
    public typealias Body = Never

    private enum Content {
        case system(title: String, systemImage: String)
        case custom(title: [AnyView], icon: [AnyView])
    }

    private let content: Content
    private var color: Color
    private var font: Font
    private var spacing: Double

    public init(_ title: String, systemImage: String) {
        self.content = .system(title: title, systemImage: systemImage)
        self.color = .white
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String) {
        self.init(String(title), systemImage: systemImage)
    }

    public init(@ViewBuilder title: () -> [AnyView], @ViewBuilder icon: () -> [AnyView]) {
        self.content = .custom(title: title(), icon: icon())
        self.color = .white
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public var body: Never {
        fatalError("Label has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let icon: [AnyView]
        let title: [AnyView]

        switch content {
        case .system(let labelTitle, let systemImage):
            icon = [
                AnyView(Image(systemName: systemImage))
            ]
            title = [
                AnyView(
                    Text(labelTitle)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                )
            ]
        case .custom(let customTitle, let customIcon):
            icon = customIcon
            title = customTitle
        }

        return HStack(spacing: spacing) {
            icon
            title
        }
        .foregroundColor(color)
        .font(font)
        .makeComponent(context: context)
    }

    public func foregroundColor(_ color: Color?) -> Label {
        guard let color else {
            return self
        }

        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color?) -> Label {
        foregroundColor(color)
    }

    public func font(_ font: Font?) -> Label {
        guard let font else {
            return self
        }

        var copy = self
        copy.font = font
        return copy
    }
}

@MainActor
public struct ContentUnavailableView: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let description: [AnyView]
    private let actions: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder description: () -> [AnyView] = { [] },
        @ViewBuilder actions: () -> [AnyView] = { [] }
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                description
            }
        }
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, description: Text? = nil) {
        self.init(String(title), systemImage: systemImage, description: description)
    }

    public static var search: ContentUnavailableView {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("Try a different search.")
        )
    }

    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView(
            "No Results for \"\(text)\"",
            systemImage: "magnifyingglass",
            description: Text("Check the spelling or try another query.")
        )
    }

    public var body: Never {
        fatalError("ContentUnavailableView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        VStack(alignment: .center, spacing: 12) {
            VStack(alignment: .center, spacing: 8) {
                label
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .font(.title3)

            if !description.isEmpty {
                VStack(alignment: .center, spacing: 4) {
                    description
                }
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.76, green: 0.84, blue: 0.94, alpha: 0.76))
                .font(.callout)
            }

            if !actions.isEmpty {
                HStack(spacing: 8) {
                    actions
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .center)
        .makeComponent(context: context)
    }
}

@MainActor
public struct LabeledContent: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.5, weight: .regular))
                    .foregroundColor(Color(red: 0.82, green: 0.88, blue: 1.0, alpha: 0.74))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.content = content()
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ title: String, value: String) {
        self.init(title) {
            Text(value)
                .font(.system(size: 1.5, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }

    public init<Title: StringProtocol, Value: StringProtocol>(_ title: Title, value: Value) {
        self.init(String(title), value: String(value))
    }

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public var body: Never {
        fatalError("LabeledContent has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        HStack(spacing: 12) {
            label
            Spacer()
            content
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct ControlGroup: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("ControlGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.horizontal)
        return Component { runtime in
            Controls.stackPanel(
                backgroundColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.58),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.12),
                shadowOffset: Point(x: 0, y: 10),
                shadowSpread: 6,
                cornerRadius: 18,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: 4,
                    padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct TextField: View {
    public typealias Body = Never

    private let title: String
    private let prompt: String?
    private let text: Binding<String>
    private var isEnabled: Bool
    private var textColor: Color

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.prompt = nil
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(String(title), text: text)
    }

    public init(_ title: String, text: Binding<String>, prompt: Text?) {
        self.title = title
        self.prompt = prompt?.promptContent
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.init(String(title), text: text, prompt: prompt)
    }

    public init(text: Binding<String>, prompt: Text) {
        self.init("", text: text, prompt: prompt)
    }

    public var body: Never {
        fatalError("TextField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.textField(
                runtime: runtime,
                text: text.wrappedValue,
                placeholder: prompt ?? title,
                isEnabled: isEnabled,
                textColor: textColor,
                onTextChanged: { newText in
                    text.wrappedValue = newText
                    text.invalidateContextIfNeeded(context)
                },
                onSubmit: context.submitAction
            )
        }
    }

    public func disabled(_ disabled: Bool) -> TextField {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func foregroundColor(_ color: Color?) -> TextField {
        guard let color else {
            return self
        }

        var copy = self
        copy.textColor = color
        return copy
    }
}

@MainActor
public struct SecureField: View {
    public typealias Body = Never

    private let title: String
    private let prompt: String?
    private let text: Binding<String>
    private var isEnabled: Bool
    private var textColor: Color

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.prompt = nil
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {
        self.init(String(title), text: text)
    }

    public init(_ title: String, text: Binding<String>, prompt: Text?) {
        self.title = title
        self.prompt = prompt?.promptContent
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {
        self.init(String(title), text: text, prompt: prompt)
    }

    public init(text: Binding<String>, prompt: Text) {
        self.init("", text: text, prompt: prompt)
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.textField(
                runtime: runtime,
                text: text.wrappedValue,
                placeholder: prompt ?? title,
                isEnabled: isEnabled,
                textColor: textColor,
                isSecure: true,
                onTextChanged: { newText in
                    text.wrappedValue = newText
                    text.invalidateContextIfNeeded(context)
                },
                onSubmit: context.submitAction
            )
        }
    }

    public func disabled(_ disabled: Bool) -> SecureField {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func foregroundColor(_ color: Color?) -> SecureField {
        guard let color else {
            return self
        }

        var copy = self
        copy.textColor = color
        return copy
    }
}

@MainActor
public struct TextEditor: View {
    public typealias Body = Never

    private let text: Binding<String>
    private var isEnabled: Bool
    private var textColor: Color

    public init(text: Binding<String>) {
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public var body: Never {
        fatalError("TextEditor has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.textEditor(
                runtime: runtime,
                text: text.wrappedValue,
                isEnabled: isEnabled,
                textColor: textColor,
                onTextChanged: { newText in
                    text.wrappedValue = newText
                    text.invalidateContextIfNeeded(context)
                }
            )
        }
    }

    public func disabled(_ disabled: Bool) -> TextEditor {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func foregroundColor(_ color: Color?) -> TextEditor {
        guard let color else {
            return self
        }

        var copy = self
        copy.textColor = color
        return copy
    }
}

@MainActor
public struct Spacer: View {
    public typealias Body = Never

    private let minLength: Double?

    public init(minLength: Double? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(
                preferredSize: Size(width: minLength ?? 0, height: minLength ?? 0),
                layoutPriority: 1,
                isHitTestVisible: false
            )
        }
    }
}

@MainActor
public struct Divider: View {
    public typealias Body = Never

    private static let defaultColor = Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.16)

    public init() {}

    public var body: Never {
        fatalError("Divider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let axis = context.containerAxis ?? .vertical
        let size: Size
        switch axis {
        case .horizontal:
            size = Size(width: 1, height: max(1, context.canvasSize.height))
        case .vertical:
            size = Size(width: max(1, context.canvasSize.width), height: 1)
        }

        return Component { _ in
            Controls.panel(
                preferredSize: size,
                backgroundColor: Self.defaultColor,
                isHitTestVisible: false
            )
        }
    }
}

@MainActor
public struct VStack: View {
    public typealias Body = Never

    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let content: [AnyView]

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.vertical)
        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .vertical(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct HStack: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: Double
    private let content: [AnyView]

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.horizontal)
        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct LazyVStack: View {
    public typealias Body = Never

    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = pinnedViews
        return VStack(alignment: alignment, spacing: spacing) {
            content
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct LazyHStack: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = pinnedViews
        return HStack(alignment: alignment, spacing: spacing) {
            content
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct LazyVGrid: View {
    public typealias Body = Never

    private let columns: [GridItem]
    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVGrid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.vertical)
        let gridLayout = resolvedGridLayout(for: context.canvasSize.width)

        return Component { runtime in
            _ = alignment
            _ = pinnedViews
            return Controls.gridPanel(
                gridLayout: gridLayout,
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }

    private func resolvedGridLayout(for availableWidth: Double) -> GridLayout {
        let columnSpacing = columns.compactMap(\.spacing).first ?? spacing
        let safeAvailableWidth = max(0, availableWidth)

        if let adaptive = columns.first(where: { item in
            if case .adaptive = item.size {
                return true
            }
            return false
        }), case let .adaptive(minimum, maximum) = adaptive.size {
            let minimumWidth = max(1, minimum)
            let maximumWidth = maximum.isFinite ? max(minimumWidth, maximum) : .infinity
            let rawCount = Int((safeAvailableWidth + columnSpacing) / (minimumWidth + columnSpacing))
            let columnCount = max(1, rawCount)
            let spacingTotal = columnSpacing * Double(max(0, columnCount - 1))
            let proposedWidth = max(minimumWidth, (safeAvailableWidth - spacingTotal) / Double(columnCount))
            let columnWidth = maximumWidth.isFinite ? min(maximumWidth, proposedWidth) : proposedWidth
            return GridLayout(
                columns: columnCount,
                rowSpacing: spacing,
                columnSpacing: columnSpacing,
                columnWidths: Array(repeating: columnWidth, count: columnCount)
            )
        }

        let resolvedColumns = columns.isEmpty ? [GridItem()] : columns
        let columnCount = resolvedColumns.count
        let spacingTotal = columnSpacing * Double(max(0, columnCount - 1))
        let fixedTotal = resolvedColumns.reduce(0.0) { total, item in
            if case let .fixed(width) = item.size {
                return total + max(0, width)
            }
            return total
        }
        let flexibleItems = resolvedColumns.filter { item in
            if case .flexible = item.size {
                return true
            }
            return false
        }
        let remainingWidth = max(0, safeAvailableWidth - spacingTotal - fixedTotal)
        let defaultFlexibleWidth = flexibleItems.isEmpty ? 0 : remainingWidth / Double(flexibleItems.count)

        let widths = resolvedColumns.map { item -> Double in
            switch item.size {
            case .fixed(let width):
                return max(0, width)
            case .flexible(let minimum, let maximum):
                let minimumWidth = max(0, minimum)
                let maximumWidth = maximum.isFinite ? max(minimumWidth, maximum) : .infinity
                let flexibleWidth = max(minimumWidth, defaultFlexibleWidth)
                return maximumWidth.isFinite ? min(maximumWidth, flexibleWidth) : flexibleWidth
            case .adaptive(let minimum, let maximum):
                let maximumWidth = maximum.isFinite ? max(minimum, maximum) : .infinity
                return maximumWidth.isFinite ? min(maximumWidth, max(0, minimum)) : max(0, minimum)
            }
        }

        return GridLayout(
            columns: columnCount,
            rowSpacing: spacing,
            columnSpacing: columnSpacing,
            columnWidths: widths
        )
    }
}

@MainActor
public struct LazyHGrid: View {
    public typealias Body = Never

    private let rows: [GridItem]
    private let alignment: VerticalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHGrid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.vertical)
        let rowMetrics = resolvedRowMetrics(for: context.canvasSize.height)

        return Component { runtime in
            _ = pinnedViews
            let columnNodes = columnGroups(rowCount: rowMetrics.heights.count).map { columnViews in
                let rowNodes = columnViews.enumerated().map { index, view -> ViewNode in
                    let child = view.makeComponent(context: childContext).makeNode(runtime: runtime)
                    let rowHeight = rowMetrics.heights[index]
                    guard rowHeight > 0 else {
                        return child
                    }

                    return Controls.panel(
                        preferredSize: Size(width: 0, height: rowHeight),
                        layoutMode: .absolute,
                        isHitTestVisible: false,
                        children: [child]
                    )
                }

                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: rowMetrics.spacing, alignment: .stretch),
                    isHitTestVisible: false,
                    children: rowNodes
                )
            }

            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: columnNodes
            )
        }
    }

    private func columnGroups(rowCount: Int) -> [[AnyView]] {
        let safeRowCount = max(1, rowCount)
        var columns: [[AnyView]] = []
        var currentColumn: [AnyView] = []

        for (index, view) in content.enumerated() {
            if index > 0, index % safeRowCount == 0 {
                columns.append(currentColumn)
                currentColumn = []
            }

            currentColumn.append(view)
        }

        if !currentColumn.isEmpty {
            columns.append(currentColumn)
        }

        return columns
    }

    private func resolvedRowMetrics(for availableHeight: Double) -> (spacing: Double, heights: [Double]) {
        let rowSpacing = rows.compactMap(\.spacing).first ?? spacing
        let safeAvailableHeight = max(0, availableHeight)

        if let adaptive = rows.first(where: { item in
            if case .adaptive = item.size {
                return true
            }
            return false
        }), case let .adaptive(minimum, maximum) = adaptive.size {
            let minimumHeight = max(1, minimum)
            let maximumHeight = maximum.isFinite ? max(minimumHeight, maximum) : .infinity
            let rawCount = Int((safeAvailableHeight + rowSpacing) / (minimumHeight + rowSpacing))
            let rowCount = max(1, rawCount)
            let spacingTotal = rowSpacing * Double(max(0, rowCount - 1))
            let proposedHeight = max(minimumHeight, (safeAvailableHeight - spacingTotal) / Double(rowCount))
            let rowHeight = maximumHeight.isFinite ? min(maximumHeight, proposedHeight) : proposedHeight
            return (rowSpacing, Array(repeating: rowHeight, count: rowCount))
        }

        let resolvedRows = rows.isEmpty ? [GridItem()] : rows
        let spacingTotal = rowSpacing * Double(max(0, resolvedRows.count - 1))
        let fixedTotal = resolvedRows.reduce(0.0) { total, item in
            if case let .fixed(height) = item.size {
                return total + max(0, height)
            }
            return total
        }
        let flexibleItems = resolvedRows.filter { item in
            if case .flexible = item.size {
                return true
            }
            return false
        }
        let remainingHeight = max(0, safeAvailableHeight - spacingTotal - fixedTotal)
        let defaultFlexibleHeight = flexibleItems.isEmpty ? 0 : remainingHeight / Double(flexibleItems.count)

        let heights = resolvedRows.map { item -> Double in
            switch item.size {
            case .fixed(let height):
                return max(0, height)
            case .flexible(let minimum, let maximum):
                let minimumHeight = max(0, minimum)
                let maximumHeight = maximum.isFinite ? max(minimumHeight, maximum) : .infinity
                let flexibleHeight = max(minimumHeight, defaultFlexibleHeight)
                return maximumHeight.isFinite ? min(maximumHeight, flexibleHeight) : flexibleHeight
            case .adaptive(let minimum, let maximum):
                let maximumHeight = maximum.isFinite ? max(minimum, maximum) : .infinity
                return maximumHeight.isFinite ? min(maximumHeight, max(0, minimum)) : max(0, minimum)
            }
        }

        return (rowSpacing, heights)
    }
}

@MainActor
public struct ZStack: View {
    public typealias Body = Never

    private let alignment: Alignment
    private let content: [AnyView]

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("ZStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let childNodes = content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            let root = Controls.panel(layoutMode: .absolute, isHitTestVisible: false, children: childNodes)
            root.onLayout = { bounds in
                for child in childNodes {
                    let childSize = child.intrinsicContentSize()
                    let origin = alignment.frameOrigin(for: childSize, in: bounds.size)
                    let frame = Rect(origin: origin, size: childSize)
                    if child.frame != frame {
                        child.frame = frame
                    }
                }
            }
            return root
        }
    }
}

@MainActor
public struct GeometryReader: View {
    public typealias Body = Never

    private let content: (GeometryProxy) -> [AnyView]

    public init(@ViewBuilder content: @escaping (GeometryProxy) -> [AnyView]) {
        self.content = content
    }

    public var body: Never {
        fatalError("GeometryReader has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content(GeometryProxy(size: context.canvasSize)),
            context: context,
            fallbackLayout: .absolute
        )
    }
}

@MainActor
public struct ScrollView: View {
    public typealias Body = Never

    private let axis: Axis
    private let style: ScrollViewStyle
    private let content: [AnyView]

    public init(_ axis: Axis = .vertical, style: ScrollViewStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.axis = axis
        self.style = style
        self.content = content()
    }

    public var body: Never {
        fatalError("ScrollView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(axis)
        return Component { runtime in
            Controls.scrollPanel(
                axis: axis.scrollAxis,
                backgroundColor: style.backgroundColor,
                borderColor: style.borderColor,
                borderWidth: style.borderWidth,
                shadowColor: style.shadowColor,
                shadowOffset: style.shadowOffset,
                shadowSpread: style.shadowSpread,
                cornerRadius: style.cornerRadius,
                stackLayout: scrollStackLayout,
                scrollStep: style.scrollStep,
                scrollIndicatorColor: style.indicatorColor,
                scrollIndicatorHoverColor: style.indicatorHoverColor,
                scrollIndicatorActiveColor: style.indicatorActiveColor,
                scrollIndicatorThickness: style.indicatorThickness,
                isHitTestVisible: style.isHitTestVisible,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }

    private var scrollStackLayout: StackLayout {
        switch axis {
        case .horizontal:
            return .horizontal(spacing: style.spacing, padding: style.padding, alignment: .center)
        case .vertical:
            return .vertical(spacing: style.spacing, padding: style.padding, alignment: style.alignment.stackAlignment)
        }
    }
}

@MainActor
public struct List: View {
    public typealias Body = Never

    private let style: ScrollViewStyle?
    private let content: [AnyView]

    public init(style: ScrollViewStyle? = nil, @ViewBuilder content: () -> [AnyView]) {
        self.style = style
        self.content = content()
    }

    public var body: Never {
        fatalError("List has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let resolvedStyle = style ?? context.listStyle?.scrollViewStyle ?? List.defaultStyle
        return ScrollView(.vertical, style: resolvedStyle) {
            content
        }
        .makeComponent(context: context)
    }

    public static let defaultStyle = ListStyle.automatic.scrollViewStyle
}

@MainActor
public struct Form: View {
    public typealias Body = Never

    private let style: ScrollViewStyle
    private let content: [AnyView]

    public init(style: ScrollViewStyle = Form.defaultStyle, @ViewBuilder content: () -> [AnyView]) {
        self.style = style
        self.content = content()
    }

    public var body: Never {
        fatalError("Form has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ScrollView(.vertical, style: style) {
            content
        }
        .makeComponent(context: context)
    }

    public static let defaultStyle = ScrollViewStyle(
        spacing: 10,
        padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
        alignment: .leading,
        backgroundColor: Color(red: 0.10, green: 0.13, blue: 0.18, alpha: 0.60),
        borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
        borderWidth: 1,
        shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.18),
        shadowOffset: Point(x: 0, y: 18),
        shadowSpread: 10,
        cornerRadius: 22,
        scrollStep: 44
    )
}

@MainActor
public struct TabView: View {
    public typealias Body = Never

    @State private var unboundSelection = 0

    private let selection: AnyTabSelectionBinding?
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.selection = nil
        self.content = content()
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.selection = AnyTabSelectionBinding(selection)
        self.content = content()
    }

    public var body: Never {
        fatalError("TabView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let tabs = makeTabs(context: context, runtime: runtime)
            guard !tabs.isEmpty else {
                return Controls.panel(preferredSize: .zero, isHitTestVisible: false)
            }

            let selectedValue = selection?.wrappedValue ?? AnyHashable(unboundSelection)
            let selectedIndex = tabs.firstIndex { $0.selectionValue == selectedValue } ?? 0
            let resolvedSelectedIndex = tabs.indices.contains(selectedIndex) ? selectedIndex : 0
            let selectedNode = tabs[resolvedSelectedIndex].contentNode
            selectedNode.layoutPriority = 1
            selectedNode.fillsAvailableWidth = true
            selectedNode.fillsAvailableHeight = true

            let tabButtons = tabs.enumerated().map { index, tab in
                makeTabButton(
                    tab: tab,
                    isSelected: index == resolvedSelectedIndex,
                    context: context,
                    runtime: runtime
                )
            }
            let tabBar = Controls.stackPanel(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.58),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 18,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: 6,
                    padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: tabButtons
            )

            return Controls.stackPanel(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.16, alpha: 0.76),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.16),
                shadowOffset: Point(x: 0, y: 16),
                shadowSpread: 10,
                cornerRadius: 24,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: 12,
                    padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: [tabBar, selectedNode]
            )
        }
    }

    private func makeTabs(context: ViewBuildContext, runtime: RetainedViewRuntime) -> [TabDescriptor] {
        content.enumerated().map { index, view in
            let node = view.makeComponent(context: context).makeNode(runtime: runtime)
            let selectionValue = node.selectionTag ?? AnyHashable(index)
            return TabDescriptor(
                index: index,
                selectionValue: selectionValue,
                title: node.tabItemTitle ?? firstText(in: node) ?? node.nodeTag ?? "Tab \(index + 1)",
                contentNode: node
            )
        }
    }

    private func makeTabButton(
        tab: TabDescriptor,
        isSelected: Bool,
        context: ViewBuildContext,
        runtime: RetainedViewRuntime
    ) -> ViewNode {
        let label = Controls.label(
            tab.title.uppercased(),
            color: isSelected
                ? Color(red: 0.94, green: 0.98, blue: 1.0, alpha: 0.98)
                : Color(red: 0.72, green: 0.80, blue: 0.90, alpha: 0.78),
            scale: 1.25,
            weight: isSelected ? .semibold : .regular,
            alignment: .center,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        let labelHost = Controls.stackPanel(
            stackLayout: .horizontal(
                spacing: 0,
                padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                alignment: .center,
                mainAlignment: .center
            ),
            isHitTestVisible: false,
            children: [label]
        )
        let surfaceStyle = isSelected ? Self.selectedTabSurface : Self.inactiveTabSurface
        let button = Controls.button(
            runtime: runtime,
            cornerRadius: surfaceStyle.cornerRadius,
            palette: surfaceStyle.palette,
            chrome: surfaceStyle.chrome,
            clipsToBounds: true,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            animation: surfaceStyle.animation,
            action: {
                if let selection {
                    selection.update(to: tab.selectionValue, context: context)
                } else {
                    unboundSelection = tab.index
                    context.invalidate()
                }
            },
            children: [labelHost]
        )
        button.nodeTag = "tab:\(String(describing: tab.selectionValue.base))"
        return button
    }

    private static let selectedTabSurface = ButtonSurfaceStyle(
        cornerRadius: 14,
        palette: SurfacePalette(
            idle: Color(red: 0.23, green: 0.34, blue: 0.48, alpha: 0.84),
            hovered: Color(red: 0.27, green: 0.40, blue: 0.56, alpha: 0.90),
            focused: Color(red: 0.30, green: 0.46, blue: 0.64, alpha: 0.94),
            pressed: Color(red: 0.36, green: 0.54, blue: 0.72, alpha: 0.98),
            activated: Color(red: 0.42, green: 0.62, blue: 0.82, alpha: 1.0)
        ),
        chrome: SurfaceChrome(
            borderColor: Color(red: 0.90, green: 0.96, blue: 1.0, alpha: 0.20),
            borderHoveredColor: Color(red: 0.94, green: 0.98, blue: 1.0, alpha: 0.30),
            borderFocusedColor: Color(red: 0.96, green: 0.99, blue: 1.0, alpha: 0.40),
            borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.46),
            borderWidth: 1,
            focusRingColor: Color(red: 0.62, green: 0.80, blue: 1.0, alpha: 0.34),
            focusRingWidth: 2,
            shadowColor: Color(red: 0.02, green: 0.08, blue: 0.16, alpha: 0.16),
            shadowHoveredColor: Color(red: 0.02, green: 0.10, blue: 0.20, alpha: 0.22),
            shadowFocusedColor: Color(red: 0.04, green: 0.14, blue: 0.26, alpha: 0.26),
            shadowPressedColor: Color(red: 0.02, green: 0.06, blue: 0.12, alpha: 0.12),
            shadowOffset: Point(x: 0, y: 8),
            shadowSpread: 6
        )
    )

    private static let inactiveTabSurface = ButtonSurfaceStyle(
        cornerRadius: 14,
        palette: SurfacePalette(
            idle: Color(red: 0.12, green: 0.16, blue: 0.23, alpha: 0.16),
            hovered: Color(red: 0.18, green: 0.24, blue: 0.34, alpha: 0.44),
            focused: Color(red: 0.22, green: 0.30, blue: 0.42, alpha: 0.56),
            pressed: Color(red: 0.26, green: 0.36, blue: 0.50, alpha: 0.66),
            activated: Color(red: 0.28, green: 0.40, blue: 0.56, alpha: 0.72)
        ),
        chrome: SurfaceChrome(
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.04),
            borderHoveredColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
            borderFocusedColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.20),
            borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.24),
            borderWidth: 1,
            focusRingColor: Color(red: 0.62, green: 0.80, blue: 1.0, alpha: 0.24),
            focusRingWidth: 2
        )
    )
}

@MainActor
public struct NavigationStack: View {
    public typealias Body = Never

    @State private var routes: [NavigationRoute] = []

    private let root: [AnyView]

    public init(@ViewBuilder root: () -> [AnyView]) {
        self.root = root()
    }

    public var body: Never {
        fatalError("NavigationStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let activeRoute = routes.last
            let activeViews = activeRoute?.destination ?? root
            let contentNode = NavigationStackScope.withPush({ route in
                routes.append(route)
                context.invalidate()
            }) {
                composeComponent(
                    from: activeViews,
                    context: context,
                    fallbackLayout: .stack(.vertical(spacing: 10, alignment: .stretch))
                )
                .makeNode(runtime: runtime)
            }
            contentNode.layoutPriority = 1
            contentNode.fillsAvailableWidth = true
            contentNode.fillsAvailableHeight = true

            var children: [ViewNode] = []
            if let activeRoute {
                children.append(makeNavigationBar(title: activeRoute.title, runtime: runtime, context: context))
            }
            children.append(contentNode)

            return Controls.stackPanel(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.16, alpha: 0.78),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.16),
                shadowOffset: Point(x: 0, y: 16),
                shadowSpread: 10,
                cornerRadius: 24,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: 12,
                    padding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private func makeNavigationBar(title: String, runtime: RetainedViewRuntime, context: ViewBuildContext) -> ViewNode {
        let backLabel = Controls.label(
            "<",
            color: Color(red: 0.94, green: 0.98, blue: 1.0, alpha: 0.94),
            scale: 1.5,
            weight: .semibold,
            alignment: .center,
            lineBreakMode: .clip,
            maximumNumberOfLines: 1
        )
        let backButton = Controls.button(
            runtime: runtime,
            preferredSize: Size(width: 36, height: 30),
            cornerRadius: 14,
            palette: Self.navigationButtonPalette,
            chrome: Self.navigationButtonChrome,
            clipsToBounds: true,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            action: {
                if !routes.isEmpty {
                    _ = routes.removeLast()
                    context.invalidate()
                }
            },
            children: [backLabel]
        )

        let titleLabel = Controls.label(
            title.uppercased(),
            layoutPriority: 1,
            color: Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.94),
            scale: 1.45,
            weight: .semibold,
            alignment: .leading,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.09, green: 0.13, blue: 0.20, alpha: 0.62),
            borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 18,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 10,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 12),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: [backButton, titleLabel]
        )
    }

    private static let navigationButtonPalette = SurfacePalette(
        idle: Color(red: 0.16, green: 0.22, blue: 0.32, alpha: 0.70),
        hovered: Color(red: 0.22, green: 0.30, blue: 0.42, alpha: 0.82),
        focused: Color(red: 0.26, green: 0.38, blue: 0.54, alpha: 0.90),
        pressed: Color(red: 0.32, green: 0.48, blue: 0.66, alpha: 0.96),
        activated: Color(red: 0.40, green: 0.58, blue: 0.78, alpha: 1.0)
    )

    private static let navigationButtonChrome = SurfaceChrome(
        borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
        borderHoveredColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.18),
        borderFocusedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.28),
        borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
        borderWidth: 1,
        focusRingColor: Color(red: 0.62, green: 0.80, blue: 1.0, alpha: 0.26),
        focusRingWidth: 2
    )
}

@MainActor
public struct NavigationLink: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let destination: [AnyView]
    private let explicitTitle: String?

    public init(_ title: String, @ViewBuilder destination: () -> [AnyView]) {
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.55, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.94))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.destination = destination()
        self.explicitTitle = title
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> [AnyView]) {
        self.init(String(title), destination: destination)
    }

    public init(
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.explicitTitle = nil
    }

    public var body: Never {
        fatalError("NavigationLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = HStack(spacing: 10) {
            label
            Spacer()
            Text(">")
                .font(.system(size: 1.5, weight: .semibold))
                .foregroundColor(Color(red: 0.72, green: 0.82, blue: 0.94, alpha: 0.82))
                .lineLimit(1)
        }
        .makeComponent(context: context)
        let push = NavigationStackScope.push

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let routeTitle = explicitTitle ?? firstText(in: labelNode) ?? "Detail"
            return Controls.button(
                runtime: runtime,
                cornerRadius: 16,
                palette: Self.linkPalette,
                chrome: Self.linkChrome,
                isEnabled: push != nil,
                clipsToBounds: true,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                action: {
                    push?(NavigationRoute(title: routeTitle, destination: destination))
                },
                children: [labelNode]
            )
        }
    }

    private static let linkPalette = SurfacePalette(
        idle: Color(red: 0.12, green: 0.17, blue: 0.25, alpha: 0.68),
        hovered: Color(red: 0.17, green: 0.24, blue: 0.34, alpha: 0.78),
        focused: Color(red: 0.22, green: 0.32, blue: 0.45, alpha: 0.86),
        pressed: Color(red: 0.28, green: 0.42, blue: 0.58, alpha: 0.94),
        activated: Color(red: 0.36, green: 0.52, blue: 0.70, alpha: 0.98)
    )

    private static let linkChrome = SurfaceChrome(
        borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
        borderHoveredColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.18),
        borderFocusedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.28),
        borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
        borderWidth: 1,
        focusRingColor: Color(red: 0.62, green: 0.80, blue: 1.0, alpha: 0.28),
        focusRingWidth: 2
    )
}

public enum ToolbarItemPlacement: Sendable, Equatable {
    case automatic
    case primaryAction
    case secondaryAction
    case navigation
    case principal
    case confirmationAction
    case cancellationAction
    case destructiveAction
    case bottomBar
}

@MainActor
public struct ToolbarItem: View {
    public typealias Body = Never

    private let placement: ToolbarItemPlacement
    private let content: [AnyView]

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> [AnyView]) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItem has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = placement
        return composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center))
        )
    }
}

@MainActor
public struct ToolbarItemGroup: View {
    public typealias Body = Never

    private let placement: ToolbarItemPlacement
    private let content: [AnyView]

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> [AnyView]) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItemGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = placement
        return HStack(spacing: 8) {
            content
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct NavigationSplitView: View {
    public typealias Body = Never

    private let sidebar: [AnyView]
    private let content: [AnyView]
    private let detail: [AnyView]
    private let usesContentColumn: Bool

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        self.usesContentColumn = true
    }

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.sidebar = sidebar()
        self.content = []
        self.detail = detail()
        self.usesContentColumn = false
    }

    public var body: Never {
        fatalError("NavigationSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        if usesContentColumn {
            return HSplitView(
                ratio: 0.28,
                minPrimaryExtent: 180,
                minSecondaryExtent: 360,
                dividerThickness: 12
            ) {
                NavigationSplitColumn(kind: .sidebar, content: sidebar)
                HSplitView(
                    ratio: 0.44,
                    minPrimaryExtent: 220,
                    minSecondaryExtent: 260,
                    dividerThickness: 12
                ) {
                    NavigationSplitColumn(kind: .content, content: content)
                    NavigationSplitColumn(kind: .detail, content: detail)
                }
            }
            .makeComponent(context: context)
        }

        return HSplitView(
            ratio: 0.30,
            minPrimaryExtent: 180,
            minSecondaryExtent: 300,
            dividerThickness: 12
        ) {
            NavigationSplitColumn(kind: .sidebar, content: sidebar)
            NavigationSplitColumn(kind: .detail, content: detail)
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct GroupBox: View {
    public typealias Body = Never

    private let title: String?
    private let style: SectionStyle
    private let label: [AnyView]
    private let content: [AnyView]

    public init(_ title: String, style: SectionStyle = GroupBox.defaultStyle, @ViewBuilder content: () -> [AnyView]) {
        self.title = title
        self.style = style
        self.label = []
        self.content = content()
    }

    public init<S: StringProtocol>(_ title: S, style: SectionStyle = GroupBox.defaultStyle, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), style: style, content: content)
    }

    public init(style: SectionStyle = GroupBox.defaultStyle, @ViewBuilder content: () -> [AnyView]) {
        self.title = nil
        self.style = style
        self.label = []
        self.content = content()
    }

    public init(
        style: SectionStyle = GroupBox.defaultStyle,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = nil
        self.style = style
        self.label = label()
        self.content = content()
    }

    public init<LabelContent: View>(
        style: SectionStyle = GroupBox.defaultStyle,
        label: LabelContent,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.title = nil
        self.style = style
        self.label = [AnyView(label)]
        self.content = content()
    }

    public var body: Never {
        fatalError("GroupBox has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        if let title {
            return Section(title, style: style) {
                content
            }
            .makeComponent(context: context)
        }

        return Section(style: style) {
            content
        } header: {
            label
        }
        .makeComponent(context: context)
    }

    public static let defaultStyle = SectionStyle(
        spacing: 12,
        padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
        backgroundColor: Color(red: 0.11, green: 0.15, blue: 0.22, alpha: 0.66),
        borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.12),
        shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.14),
        cornerRadius: 20,
        headerColor: Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.92),
        headerFont: .system(size: 1.35, weight: .semibold)
    )
}

@MainActor
public struct DisclosureGroup: View {
    public typealias Body = Never

    private let isExpanded: Binding<Bool>
    private let label: [AnyView]
    private let content: [AnyView]

    public init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> [AnyView]) {
        self.isExpanded = isExpanded
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.55, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.content = content()
    }

    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), isExpanded: isExpanded, content: content)
    }

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.isExpanded = isExpanded
        self.label = label()
        self.content = content()
    }

    public var body: Never {
        fatalError("DisclosureGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                isExpanded.wrappedValue = !isExpanded.wrappedValue
            }) {
                HStack(spacing: 8) {
                    Text(isExpanded.wrappedValue ? "v" : ">")
                        .font(.system(size: 1.2, weight: .semibold))
                        .foregroundColor(Color(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.88))
                        .frame(width: 18)
                    label
                }
            }
            .buttonStyle(.borderless)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.leading, 26)
            }
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct Section: View {
    public typealias Body = Never

    private let title: String?
    private let style: SectionStyle
    private let header: [AnyView]
    private let content: [AnyView]
    private let footer: [AnyView]

    public init(_ title: String, style: SectionStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.title = title
        self.style = style
        self.header = []
        self.content = content()
        self.footer = []
    }

    public init<S: StringProtocol>(_ title: S, style: SectionStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), style: style, content: content)
    }

    public init(
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView] = { [] },
        @ViewBuilder footer: () -> [AnyView] = { [] }
    ) {
        self.title = nil
        self.style = style
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    public init(
        style: SectionStyle = .default,
        @ViewBuilder header: () -> [AnyView],
        @ViewBuilder footer: () -> [AnyView] = { [] },
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.title = nil
        self.style = style
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    public var body: Never {
        fatalError("Section has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withContainerAxis(.vertical)
        return Component { runtime in
            let sectionChildren = makeSectionChildren(context: childContext, runtime: runtime)
            let node = Controls.stackPanel(
                backgroundColor: style.backgroundColor,
                backgroundGradient: style.backgroundGradient,
                borderColor: style.borderColor,
                borderWidth: 1,
                shadowColor: style.shadowColor,
                shadowOffset: Point(x: 0, y: 20),
                shadowSpread: 10,
                cornerRadius: style.cornerRadius,
                clipsToBounds: true,
                stackLayout: .vertical(spacing: style.spacing, padding: style.padding, alignment: style.alignment.stackAlignment),
                isHitTestVisible: style.isHitTestVisible,
                children: sectionChildren
            )

            if let scrollAxis = style.scrollAxis {
                node.scrollAxis = scrollAxis.scrollAxis
                node.scrollStep = style.scrollStep
                node.showsScrollIndicator = true
                node.scrollIndicatorColor = style.indicatorColor
                node.scrollIndicatorIdleColor = style.indicatorColor
                node.scrollIndicatorHoverColor = style.indicatorHoverColor
                node.scrollIndicatorActiveColor = style.indicatorActiveColor
                node.scrollIndicatorThickness = style.indicatorThickness
            }

            return node
        }
    }

    private func makeSectionChildren(context: ViewBuildContext, runtime: RetainedViewRuntime) -> [ViewNode] {
        var nodes: [ViewNode] = []

        if let title {
            nodes.append(
                Controls.label(
                    title,
                    color: style.headerColor,
                    scale: style.headerFont.size,
                    weight: style.headerFont.weight.textWeight,
                    alignment: .leading,
                    lineBreakMode: .truncateTail,
                    maximumNumberOfLines: 1
                )
            )
        }

        nodes.append(contentsOf: header.map { $0.makeComponent(context: context).makeNode(runtime: runtime) })
        nodes.append(contentsOf: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) })
        nodes.append(contentsOf: footer.map { $0.makeComponent(context: context).makeNode(runtime: runtime) })
        return nodes
    }
}

@MainActor
public struct Button: View {
    public typealias Body = Never

    private let action: @MainActor () -> Void
    private let label: [AnyView]
    private let role: ButtonRole?
    private var style: ButtonSurfaceStyle
    private var resolvedButtonStyle: ButtonStyle?
    private var isEnabled: Bool

    public init(role: ButtonRole? = nil, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = nil
        self.isEnabled = true
    }

    public init(_ title: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = nil
        self.isEnabled = true
    }

    public init<S: StringProtocol>(_ title: S, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.init(String(title), role: role, action: action)
    }

    public init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(
                Label(title, systemImage: systemImage)
                    .font(.system(size: 1.8, weight: .semibold))
            )
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = nil
        self.isEnabled = true
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole? = nil, action: @escaping @MainActor () -> Void) {
        self.init(String(title), systemImage: systemImage, role: role, action: action)
    }

    public var body: Never {
        fatalError("Button has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let surfaceStyle = resolvedSurfaceStyle(inheritedStyle: context.buttonStyle)
            return Controls.button(
                runtime: runtime,
                cornerRadius: surfaceStyle.cornerRadius,
                palette: surfaceStyle.palette,
                chrome: surfaceStyle.chrome,
                isEnabled: isEnabled,
                clipsToBounds: surfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                animation: surfaceStyle.animation,
                action: isEnabled ? {
                    action()
                    context.invalidate()
                } : nil,
                children: [labelNode]
            )
        }
    }

    private func resolvedSurfaceStyle(inheritedStyle: ButtonStyle?) -> ButtonSurfaceStyle {
        let effectiveButtonStyle = resolvedButtonStyle ?? inheritedStyle ?? .automatic
        if role == .destructive, effectiveButtonStyle == .automatic {
            return .destructive
        }

        return effectiveButtonStyle == .automatic ? style : effectiveButtonStyle.surfaceStyle
    }

    public func buttonSurface(_ style: ButtonSurfaceStyle) -> Button {
        var copy = self
        copy.style = style
        copy.resolvedButtonStyle = .automatic
        return copy
    }

    public func buttonStyle(_ style: ButtonStyle) -> Button {
        var copy = self
        copy.resolvedButtonStyle = style
        return copy
    }

    public func disabled(_ disabled: Bool) -> Button {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }
}

@MainActor
public struct Menu: View {
    public typealias Body = Never

    @State private var isExpanded = false

    private let label: [AnyView]
    private let content: [AnyView]

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.7, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.content = content()
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.label = [
            AnyView(
                Label(title, systemImage: systemImage)
                    .font(.system(size: 1.55, weight: .semibold))
            )
        ]
        self.content = content()
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), systemImage: systemImage, content: content)
    }

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public var body: Never {
        fatalError("Menu has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                isExpanded = !isExpanded
            }) {
                HStack(spacing: 8) {
                    label
                    Text(isExpanded ? "^" : "v")
                        .font(.system(size: 1.1, weight: .semibold))
                        .foregroundColor(Color(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.88))
                        .frame(width: 14)
                }
            }
            .buttonStyle(.bordered)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(8)
                .background(Color(red: 0.08, green: 0.12, blue: 0.19, alpha: 0.82))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10), lineWidth: 1)
                )
            }
        }
        .makeComponent(context: context)
    }
}

@MainActor
public struct Toggle: View {
    public typealias Body = Never

    private static let defaultTintColor = Color(red: 0.24, green: 0.62, blue: 1.0, alpha: 1.0)

    private let isOn: Binding<Bool>
    private let label: [AnyView]
    private var isEnabled: Bool
    private var tintColor: Color?
    private var offColor: Color
    private var hidesLabel: Bool

    public init(_ title: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.6, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.isEnabled = true
        self.tintColor = nil
        self.offColor = Color(red: 0.31, green: 0.35, blue: 0.42, alpha: 1.0)
        self.hidesLabel = false
    }

    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(String(title), isOn: isOn)
    }

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> [AnyView]) {
        self.isOn = isOn
        self.label = label()
        self.isEnabled = true
        self.tintColor = nil
        self.offColor = Color(red: 0.31, green: 0.35, blue: 0.42, alpha: 1.0)
        self.hidesLabel = false
    }

    public var body: Never {
        fatalError("Toggle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let switchNode = Controls.toggle(
                runtime: runtime,
                isOn: isOn.wrappedValue,
                isEnabled: isEnabled,
                onColor: tintColor ?? context.tintColor ?? Self.defaultTintColor,
                offColor: offColor,
                onToggle: { newValue in
                    isOn.wrappedValue = newValue
                    isOn.invalidateContextIfNeeded(context)
                }
            )

            guard !hidesLabel, !label.isEmpty else {
                return switchNode
            }

            let labelNode = composeComponent(
                from: label,
                context: context,
                fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
            ).makeNode(runtime: runtime)
            labelNode.layoutPriority = 1

            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 10, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, switchNode]
            )
        }
    }

    public func disabled(_ disabled: Bool) -> Toggle {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func tint(_ color: Color?) -> Toggle {
        guard let color else {
            return self
        }

        var copy = self
        copy.tintColor = color
        return copy
    }

    public func accentColor(_ color: Color?) -> Toggle {
        tint(color)
    }

    public func labelsHidden() -> Toggle {
        var copy = self
        copy.hidesLabel = true
        return copy
    }
}

@MainActor
public struct Stepper<Value: Comparable>: View {
    public typealias Body = Never

    private let value: Binding<Value>
    private let bounds: ClosedRange<Value>
    private let label: [AnyView]
    private let incrementValue: (Value) -> Value
    private let decrementValue: (Value) -> Value
    private let valueText: (Value) -> String
    private var isEnabled: Bool

    public init(_ title: String, value: Binding<Int>, in bounds: ClosedRange<Int> = Int.min...Int.max, step: Int = 1) where Value == Int {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: {
                Text(title)
                    .font(.system(size: 1.6, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
        )
    }

    public init<S: StringProtocol>(_ title: S, value: Binding<Int>, in bounds: ClosedRange<Int> = Int.min...Int.max, step: Int = 1) where Value == Int {
        self.init(String(title), value: value, in: bounds, step: step)
    }

    public init(value: Binding<Int>, in bounds: ClosedRange<Int> = Int.min...Int.max, step: Int = 1, @ViewBuilder label: () -> [AnyView]) where Value == Int {
        let normalizedStep = step > 0 ? step : 1
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.incrementValue = { current in
            let (candidate, overflow) = current.addingReportingOverflow(normalizedStep)
            return overflow ? Int.max : candidate
        }
        self.decrementValue = { current in
            let (candidate, overflow) = current.subtractingReportingOverflow(normalizedStep)
            return overflow ? Int.min : candidate
        }
        self.valueText = { "\($0)" }
        self.isEnabled = true
    }

    public init(_ title: String, value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1.0) where Value == Double {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: {
                Text(title)
                    .font(.system(size: 1.6, weight: .regular))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
        )
    }

    public init<S: StringProtocol>(_ title: S, value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1.0) where Value == Double {
        self.init(String(title), value: value, in: bounds, step: step)
    }

    public init(value: Binding<Double>, in bounds: ClosedRange<Double>, step: Double = 1.0, @ViewBuilder label: () -> [AnyView]) where Value == Double {
        let normalizedStep = step > 0 ? step : 1.0
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.incrementValue = { $0 + normalizedStep }
        self.decrementValue = { $0 - normalizedStep }
        self.valueText = { "\($0)" }
        self.isEnabled = true
    }

    public var body: Never {
        fatalError("Stepper has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let currentValue = clamped(value.wrappedValue)
        let canDecrement = isEnabled && currentValue > bounds.lowerBound
        let canIncrement = isEnabled && currentValue < bounds.upperBound

        return HStack(spacing: 10) {
            label
            Spacer()
            Text(valueText(currentValue))
                .font(.system(size: 1.35, weight: .semibold))
                .foregroundColor(Color(red: 0.84, green: 0.90, blue: 1.0, alpha: 0.78))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
            HStack(spacing: 6) {
                Button("-") {
                    setValue(decrementValue(value.wrappedValue))
                }
                .buttonStyle(.bordered)
                .disabled(!canDecrement)

                Button("+") {
                    setValue(incrementValue(value.wrappedValue))
                }
                .buttonStyle(.bordered)
                .disabled(!canIncrement)
            }
        }
        .makeComponent(context: context)
    }

    private func setValue(_ newValue: Value) {
        value.wrappedValue = clamped(newValue)
    }

    private func clamped(_ rawValue: Value) -> Value {
        if rawValue < bounds.lowerBound {
            return bounds.lowerBound
        }
        if rawValue > bounds.upperBound {
            return bounds.upperBound
        }
        return rawValue
    }

    public func disabled(_ disabled: Bool) -> Stepper {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }
}

@MainActor
public struct Slider: View {
    public typealias Body = Never

    private static let defaultTintColor = Color(red: 0.24, green: 0.62, blue: 1.0, alpha: 1.0)

    private let value: Binding<Double>
    private let bounds: ClosedRange<Double>
    private let step: Double?
    private var isEnabled: Bool
    private var trackColor: Color
    private var tintColor: Color?

    public init(value: Binding<Double>, in bounds: ClosedRange<Double> = 0...1, step: Double? = nil) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.isEnabled = true
        self.trackColor = Color(red: 0.30, green: 0.34, blue: 0.40, alpha: 1.0)
        self.tintColor = nil
    }

    public var body: Never {
        fatalError("Slider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.slider(
                runtime: runtime,
                value: value.wrappedValue,
                range: bounds,
                isEnabled: isEnabled,
                trackColor: trackColor,
                filledColor: tintColor ?? context.tintColor ?? Self.defaultTintColor,
                onValueChanged: { newValue in
                    value.wrappedValue = snappedValue(newValue)
                    value.invalidateContextIfNeeded(context)
                }
            )
        }
    }

    private func snappedValue(_ rawValue: Double) -> Double {
        let clampedValue = min(max(rawValue, bounds.lowerBound), bounds.upperBound)
        guard let step, step > 0 else {
            return clampedValue
        }

        let steppedOffset = ((clampedValue - bounds.lowerBound) / step).rounded() * step
        return min(max(bounds.lowerBound + steppedOffset, bounds.lowerBound), bounds.upperBound)
    }

    public func disabled(_ disabled: Bool) -> Slider {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func tint(_ color: Color?) -> Slider {
        guard let color else {
            return self
        }

        var copy = self
        copy.tintColor = color
        return copy
    }

    public func accentColor(_ color: Color?) -> Slider {
        tint(color)
    }
}

@MainActor
public struct ProgressView: View {
    public typealias Body = Never

    private static let defaultTintColor = Color(red: 0.24, green: 0.62, blue: 1.0, alpha: 1.0)

    private let title: String?
    private let value: Double?
    private let total: Double
    private var tintColor: Color?

    public init(value: Double? = nil, total: Double = 1.0) {
        self.title = nil
        self.value = value
        self.total = total
        self.tintColor = nil
    }

    public init(_ title: String, value: Double? = nil, total: Double = 1.0) {
        self.title = title
        self.value = value
        self.total = total
        self.tintColor = nil
    }

    public init<S: StringProtocol>(_ title: S, value: Double? = nil, total: Double = 1.0) {
        self.init(String(title), value: value, total: total)
    }

    public var body: Never {
        fatalError("ProgressView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            let progressBar = Controls.progressBar(
                value: value ?? 0,
                total: total,
                filledColor: tintColor ?? context.tintColor ?? Self.defaultTintColor
            )

            guard let title, !title.isEmpty else {
                return progressBar
            }

            let label = Controls.label(
                title,
                layoutPriority: 1,
                color: Color(red: 0.86, green: 0.91, blue: 0.98, alpha: 0.92),
                scale: 1.5,
                weight: .semibold,
                alignment: .leading,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [label, progressBar]
            )
        }
    }

    public func tint(_ color: Color?) -> ProgressView {
        guard let color else {
            return self
        }

        var copy = self
        copy.tintColor = color
        return copy
    }

    public func accentColor(_ color: Color?) -> ProgressView {
        tint(color)
    }
}

@MainActor
public struct Picker<SelectionValue: Hashable>: View {
    public typealias Body = Never

    private let title: String
    private let selection: Binding<SelectionValue>
    private let content: [AnyView]
    private var isEnabled: Bool
    private var hidesLabel: Bool

    public init(_ title: String = "", selection: Binding<SelectionValue>, @ViewBuilder content: () -> [AnyView]) {
        self.title = title
        self.selection = selection
        self.content = content()
        self.isEnabled = true
        self.hidesLabel = false
    }

    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), selection: selection, content: content)
    }

    public var body: Never {
        fatalError("Picker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let options: [PickerOption<SelectionValue>] = pickerOptions(from: content, context: context, runtime: runtime)
            let optionTitles = options.map(\.title)
            let selectedIndex = options.firstIndex { $0.value == selection.wrappedValue } ?? 0
            let dropdown = Controls.dropdown(
                runtime: runtime,
                options: optionTitles,
                selectedIndex: selectedIndex,
                isEnabled: isEnabled,
                onSelect: { selectedOptionIndex in
                    guard options.indices.contains(selectedOptionIndex) else {
                        return
                    }

                    selection.wrappedValue = options[selectedOptionIndex].value
                    selection.invalidateContextIfNeeded(context)
                }
            )

            guard !hidesLabel, !title.isEmpty else {
                return dropdown
            }

            let label = Controls.label(
                title,
                layoutPriority: 1,
                color: Color(red: 0.85, green: 0.90, blue: 0.98, alpha: 0.92),
                scale: 1.5,
                weight: .semibold,
                alignment: .leading,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )

            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: false,
                children: [label, dropdown]
            )
        }
    }

    public func disabled(_ disabled: Bool) -> Picker {
        var copy = self
        copy.isEnabled = !disabled
        return copy
    }

    public func labelsHidden() -> Picker {
        var copy = self
        copy.hidesLabel = true
        return copy
    }
}

@MainActor
public struct HSplitView: View {
    public typealias Body = Never

    private let ratio: Double?
    private let minPrimaryExtent: Double
    private let minSecondaryExtent: Double
    private let dividerThickness: Double
    private let dividerIdleColor: Color
    private let dividerHoverColor: Color
    private let dividerActiveColor: Color
    private let onRatioChanged: ((Double) -> Void)?
    private let content: [AnyView]

    public init(
        ratio: Double? = nil,
        minPrimaryExtent: Double = 180,
        minSecondaryExtent: Double = 220,
        dividerThickness: Double = 16,
        dividerIdleColor: Color = Color(red: 0.36, green: 0.46, blue: 0.58, alpha: 0.10),
        dividerHoverColor: Color = Color(red: 0.50, green: 0.64, blue: 0.80, alpha: 0.28),
        dividerActiveColor: Color = Color(red: 0.70, green: 0.84, blue: 0.98, alpha: 0.48),
        onRatioChanged: ((Double) -> Void)? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.ratio = ratio
        self.minPrimaryExtent = minPrimaryExtent
        self.minSecondaryExtent = minSecondaryExtent
        self.dividerThickness = dividerThickness
        self.dividerIdleColor = dividerIdleColor
        self.dividerHoverColor = dividerHoverColor
        self.dividerActiveColor = dividerActiveColor
        self.onRatioChanged = onRatioChanged
        self.content = content()
    }

    public var body: Never {
        fatalError("HSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        splitComponent(axis: .horizontal, context: context)
    }
}

@MainActor
public struct VSplitView: View {
    public typealias Body = Never

    private let ratio: Double?
    private let minPrimaryExtent: Double
    private let minSecondaryExtent: Double
    private let dividerThickness: Double
    private let dividerIdleColor: Color
    private let dividerHoverColor: Color
    private let dividerActiveColor: Color
    private let onRatioChanged: ((Double) -> Void)?
    private let content: [AnyView]

    public init(
        ratio: Double? = nil,
        minPrimaryExtent: Double = 180,
        minSecondaryExtent: Double = 220,
        dividerThickness: Double = 16,
        dividerIdleColor: Color = Color(red: 0.36, green: 0.46, blue: 0.58, alpha: 0.10),
        dividerHoverColor: Color = Color(red: 0.50, green: 0.64, blue: 0.80, alpha: 0.28),
        dividerActiveColor: Color = Color(red: 0.70, green: 0.84, blue: 0.98, alpha: 0.48),
        onRatioChanged: ((Double) -> Void)? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.ratio = ratio
        self.minPrimaryExtent = minPrimaryExtent
        self.minSecondaryExtent = minSecondaryExtent
        self.dividerThickness = dividerThickness
        self.dividerIdleColor = dividerIdleColor
        self.dividerHoverColor = dividerHoverColor
        self.dividerActiveColor = dividerActiveColor
        self.onRatioChanged = onRatioChanged
        self.content = content()
    }

    public var body: Never {
        fatalError("VSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        splitComponent(axis: .vertical, context: context)
    }
}

private extension HSplitView {
    func splitComponent(axis: SplitAxis, context: ViewBuildContext) -> Component {
        buildSplitComponent(
            content: content,
            axis: axis,
            ratio: ratio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            context: context
        )
    }
}

private extension VSplitView {
    func splitComponent(axis: SplitAxis, context: ViewBuildContext) -> Component {
        buildSplitComponent(
            content: content,
            axis: axis,
            ratio: ratio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            context: context
        )
    }
}

private enum NavigationSplitColumnKind {
    case sidebar
    case content
    case detail

    var backgroundColor: Color {
        switch self {
        case .sidebar:
            return Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
        case .content:
            return Color(red: 0.09, green: 0.13, blue: 0.20, alpha: 0.72)
        case .detail:
            return Color(red: 0.07, green: 0.10, blue: 0.16, alpha: 0.80)
        }
    }

    var borderColor: Color {
        Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.08)
    }
}

@MainActor
private struct NavigationSplitColumn: View {
    typealias Body = Never

    let kind: NavigationSplitColumnKind
    let content: [AnyView]

    var body: Never {
        fatalError("NavigationSplitColumn has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(kind.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(kind.borderColor, lineWidth: 1)
        )
        .makeComponent(context: context)
    }
}

@MainActor
private struct AnyTabSelectionBinding {
    var wrappedValue: AnyHashable {
        getter()
    }

    private let getter: @MainActor () -> AnyHashable
    private let setter: @MainActor (AnyHashable, ViewBuildContext) -> Void

    init<Value: Hashable>(_ binding: Binding<Value>) {
        self.getter = {
            AnyHashable(binding.wrappedValue)
        }
        self.setter = { value, context in
            guard let typedValue = value.base as? Value else {
                return
            }

            binding.wrappedValue = typedValue
            binding.invalidateContextIfNeeded(context)
        }
    }

    func update(to value: AnyHashable, context: ViewBuildContext) {
        setter(value, context)
    }
}

private struct TabDescriptor {
    var index: Int
    var selectionValue: AnyHashable
    var title: String
    var contentNode: ViewNode
}

private struct NavigationRoute {
    var title: String
    var destination: [AnyView]
}

@MainActor
private enum NavigationStackScope {
    private static var currentPush: ((NavigationRoute) -> Void)?

    static var push: ((NavigationRoute) -> Void)? {
        currentPush
    }

    static func withPush<Result>(_ push: @escaping (NavigationRoute) -> Void, _ body: () -> Result) -> Result {
        let previousPush = currentPush
        currentPush = push
        defer {
            currentPush = previousPush
        }
        return body()
    }
}

@MainActor
private struct NavigationTitleHost<Content: View>: View {
    typealias Body = Never

    let content: Content
    let title: String

    var body: Never {
        fatalError("NavigationTitleHost has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let contentComponent = content.makeComponent(context: context)

        return Component { runtime in
            let titleLabel = Controls.label(
                title.uppercased(),
                layoutPriority: 1,
                color: Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.96),
                scale: 2.05,
                weight: .semibold,
                alignment: .leading,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            titleLabel.fillsAvailableWidth = true

            let titleBar = Controls.stackPanel(
                backgroundColor: Color(red: 0.09, green: 0.13, blue: 0.20, alpha: 0.62),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.09),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.12),
                shadowOffset: Point(x: 0, y: 10),
                shadowSpread: 8,
                cornerRadius: 20,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: 0,
                    padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: [titleLabel]
            )
            titleBar.fillsAvailableWidth = true

            let contentNode = contentComponent.makeNode(runtime: runtime)
            contentNode.layoutPriority = 1
            contentNode.fillsAvailableWidth = true
            contentNode.fillsAvailableHeight = true

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 10, alignment: .stretch),
                isHitTestVisible: false,
                children: [titleBar, contentNode]
            )
        }
    }
}

public extension View {
    func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        NavigationTitleHost(content: self, title: String(title))
    }
}

@MainActor
private struct ToolbarHost<Content: View>: View {
    typealias Body = Never

    let content: Content
    let items: [AnyView]

    var body: Never {
        fatalError("ToolbarHost has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        guard !items.isEmpty else {
            return content.makeComponent(context: context)
        }

        let contentComponent = content.makeComponent(context: context)

        return Component { runtime in
            let toolbarChildren = items.map { item in
                item.makeComponent(context: context).makeNode(runtime: runtime)
            }
            let toolbar = Controls.stackPanel(
                backgroundColor: Color(red: 0.09, green: 0.13, blue: 0.20, alpha: 0.70),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.14),
                shadowOffset: Point(x: 0, y: 10),
                shadowSpread: 8,
                cornerRadius: 20,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                    alignment: .center,
                    mainAlignment: .end
                ),
                isHitTestVisible: false,
                children: toolbarChildren
            )
            toolbar.fillsAvailableWidth = true

            let contentNode = contentComponent.makeNode(runtime: runtime)
            contentNode.layoutPriority = 1
            contentNode.fillsAvailableWidth = true
            contentNode.fillsAvailableHeight = true

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 10, alignment: .stretch),
                isHitTestVisible: false,
                children: [toolbar, contentNode]
            )
        }
    }
}

public extension View {
    func toolbar(@ViewBuilder content: () -> [AnyView]) -> some View {
        ToolbarHost(content: self, items: content())
    }
}

@MainActor
private struct TabItemView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let label: [AnyView]

    var body: Never {
        fatalError("TabItemView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let contentComponent = content.makeComponent(context: context)
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 6, alignment: .center))
        )

        return Component { runtime in
            let node = contentComponent.makeNode(runtime: runtime)
            let labelNode = labelComponent.makeNode(runtime: runtime)
            node.tabItemTitle = lastText(in: labelNode) ?? firstText(in: labelNode)
            return node
        }
    }
}

public extension View {
    func tabItem(@ViewBuilder _ label: () -> [AnyView]) -> some View {
        TabItemView(content: self, label: label())
    }
}

@MainActor
private func buildSplitComponent(
    content: [AnyView],
    axis: SplitAxis,
    ratio: Double?,
    minPrimaryExtent: Double,
    minSecondaryExtent: Double,
    dividerThickness: Double,
    dividerIdleColor: Color,
    dividerHoverColor: Color,
    dividerActiveColor: Color,
    onRatioChanged: ((Double) -> Void)?,
    context: ViewBuildContext
) -> Component {
    let primaryViews = content.isEmpty ? [] : [content[0]]
    let secondaryViews = content.count > 1 ? Array(content.dropFirst()) : []
    let primaryComponent = composeComponent(from: primaryViews, context: context)
    let secondaryComponent = composeComponent(
        from: secondaryViews,
        context: context,
        fallbackLayout: .stack(.vertical(alignment: .stretch))
    )

    return Component { runtime in
        let primaryNode = primaryComponent.makeNode(runtime: runtime)
        let secondaryNode = secondaryComponent.makeNode(runtime: runtime)
        let defaultExtent = axis == .horizontal ? context.canvasSize.width : context.canvasSize.height
        let primaryExtent = axis == .horizontal ? primaryNode.intrinsicContentSize().width : primaryNode.intrinsicContentSize().height
        let inferredRatio = max(0.1, min(0.9, primaryExtent / max(1, defaultExtent - dividerThickness)))

        return Controls.splitView(
            runtime: runtime,
            axis: axis,
            ratio: ratio ?? inferredRatio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            primary: [primaryNode],
            secondary: [secondaryNode]
        )
    }
}

private struct PickerOption<Value: Hashable> {
    var title: String
    var value: Value
}

@MainActor
private func pickerOptions<Value: Hashable>(
    from views: [AnyView],
    context: ViewBuildContext,
    runtime: RetainedViewRuntime
) -> [PickerOption<Value>] {
    views.enumerated().compactMap { index, view in
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        guard let value = pickerSelectionValue(from: node, fallbackIndex: index, as: Value.self) else {
            return nil
        }

        return PickerOption(
            title: firstText(in: node) ?? node.nodeTag ?? "Option \(index + 1)",
            value: value
        )
    }
}

@MainActor
private func pickerSelectionValue<Value: Hashable>(
    from node: ViewNode,
    fallbackIndex: Int,
    as type: Value.Type
) -> Value? {
    if let taggedValue = node.selectionTag?.base as? Value {
        return taggedValue
    }

    if let nodeTag = node.nodeTag, let intTag = Int(nodeTag), let value = intTag as? Value {
        return value
    }

    return fallbackIndex as? Value
}

@MainActor
private func firstText(in node: ViewNode) -> String? {
    if let text = node.text, !text.isEmpty {
        return text
    }

    for child in node.children {
        if let text = firstText(in: child) {
            return text
        }
    }

    return nil
}

@MainActor
private func lastText(in node: ViewNode) -> String? {
    for child in node.children.reversed() {
        if let text = lastText(in: child) {
            return text
        }
    }

    if let text = node.text, !text.isEmpty {
        return text
    }

    return nil
}

private func resolvedSymbolIcon(for systemName: String) -> SymbolIcon {
    switch systemName {
    case "magnifyingglass":
        return .search
    case "folder":
        return .folder
    case "archivebox", "archivebox.fill", "tray", "tray.fill":
        return .folder
    case "gearshape", "gearshape.fill":
        return .settings
    case "plus", "plus.circle", "plus.circle.fill", "plus.square", "plus.square.fill":
        return .plus
    case "minus", "minus.circle", "minus.circle.fill", "minus.square", "minus.square.fill":
        return .minus
    case "xmark", "xmark.circle", "xmark.circle.fill", "xmark.square", "xmark.square.fill":
        return .xmark
    case "bolt", "bolt.fill":
        return .lightning
    case "rectangle.3.group", "square.grid.3x1.folder.badge.plus":
        return .layout
    case "keyboard":
        return .keyboard
    case "star", "star.circle", "star.square":
        return .star
    case "star.fill", "star.circle.fill", "star.square.fill":
        return .starFill
    case "sparkles":
        return .sparkle
    case "info.circle", "info.circle.fill":
        return .info
    case "waveform.path.ecg", "chart.line.uptrend.xyaxis":
        return .activity
    case "doc.text", "doc.text.fill":
        return .document
    case "rectangle.split.3x1", "rectangle.split.3x1.fill":
        return .split
    case "trash", "trash.fill", "delete.left", "delete.left.fill":
        return .trash
    case "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.square", "checkmark.square.fill":
        return .checkmark
    case "chevron.up", "chevron.up.circle", "chevron.up.circle.fill":
        return .chevronUp
    case "chevron.down", "chevron.down.circle", "chevron.down.circle.fill":
        return .chevronDown
    case "chevron.left", "chevron.left.circle", "chevron.left.circle.fill":
        return .chevronLeft
    case "chevron.right", "chevron.right.circle", "chevron.right.circle.fill":
        return .chevronRight
    case "calendar", "calendar.circle", "calendar.circle.fill":
        return .calendar
    case "person", "person.fill", "person.circle", "person.circle.fill", "person.crop.circle":
        return .person
    case "person.2", "person.2.fill", "person.2.circle", "person.2.circle.fill":
        return .people
    case "play", "play.fill", "play.circle", "play.circle.fill":
        return .play
    case "pause", "pause.fill", "pause.circle", "pause.circle.fill":
        return .pause
    case "arrow.clockwise", "arrow.clockwise.circle", "arrow.clockwise.circle.fill":
        return .refresh
    case "square.and.arrow.up", "square.and.arrow.up.fill":
        return .share
    case "lock", "lock.fill", "lock.circle", "lock.circle.fill":
        return .lock
    case "lock.open", "lock.open.fill", "lock.open.circle", "lock.open.circle.fill":
        return .unlock
    default:
        return .sparkle
    }
}
