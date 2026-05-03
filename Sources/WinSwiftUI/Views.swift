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

    private let content: String
    private var color: Color
    private var font: Font
    private var alignment: TextAlignment
    private var lineLimit: Int?

    public init(_ content: String) {
        self.content = content
        self.color = .white
        self.font = .system(size: 2)
        self.alignment = .center
        self.lineLimit = nil
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
                lineBreakMode: resolvedLineBreakMode,
                maximumNumberOfLines: lineLimit
            )
        }
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.color = color
        return copy
    }

    public func font(_ font: Font) -> Text {
        var copy = self
        copy.font = font
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ lineLimit: Int?) -> Text {
        var copy = self
        copy.lineLimit = lineLimit
        return copy
    }

    private var resolvedLineBreakMode: TextLineBreakMode {
        if let lineLimit, lineLimit == 1 {
            return .truncateTail
        }

        return .wrap
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

    public func foregroundColor(_ color: Color) -> Image {
        var copy = self
        copy.color = color
        return copy
    }

    public func font(_ font: Font) -> Image {
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

    private let title: String
    private let systemImage: String
    private var color: Color
    private var font: Font
    private var spacing: Double

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.color = .white
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public var body: Never {
        fatalError("Label has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        HStack(spacing: spacing) {
            Image(systemName: systemImage)
                .foregroundColor(color)
                .font(font)
            Text(title)
                .foregroundColor(color)
                .font(font)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
        .makeComponent(context: context)
    }

    public func foregroundColor(_ color: Color) -> Label {
        var copy = self
        copy.color = color
        return copy
    }

    public func font(_ font: Font) -> Label {
        var copy = self
        copy.font = font
        return copy
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

    public init(_ title: String, value: String) {
        self.init(title) {
            Text(value)
                .font(.system(size: 1.5, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
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
public struct TextField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private var isEnabled: Bool
    private var textColor: Color

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public var body: Never {
        fatalError("TextField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.textField(
                runtime: runtime,
                text: text.wrappedValue,
                placeholder: title,
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

    public func foregroundColor(_ color: Color) -> TextField {
        var copy = self
        copy.textColor = color
        return copy
    }
}

@MainActor
public struct SecureField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private var isEnabled: Bool
    private var textColor: Color

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
        self.isEnabled = true
        self.textColor = Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.textField(
                runtime: runtime,
                text: text.wrappedValue,
                placeholder: title,
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

    public func foregroundColor(_ color: Color) -> SecureField {
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

    public init(alignment: HorizontalAlignment = .center, spacing: Double = 0, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing
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

    public init(alignment: VerticalAlignment = .center, spacing: Double = 0, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing
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

    private let style: ScrollViewStyle
    private let content: [AnyView]

    public init(style: ScrollViewStyle = List.defaultStyle, @ViewBuilder content: () -> [AnyView]) {
        self.style = style
        self.content = content()
    }

    public var body: Never {
        fatalError("List has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ScrollView(.vertical, style: style) {
            content
        }
        .makeComponent(context: context)
    }

    public static let defaultStyle = ScrollViewStyle(
        spacing: 6,
        padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
        alignment: .leading,
        backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.54),
        borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.08),
        borderWidth: 1,
        cornerRadius: 16,
        scrollStep: 44
    )
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
    private var resolvedButtonStyle: ButtonStyle
    private var isEnabled: Bool

    public init(role: ButtonRole? = nil, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
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
        self.resolvedButtonStyle = .automatic
        self.isEnabled = true
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
        self.resolvedButtonStyle = .automatic
        self.isEnabled = true
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
            let surfaceStyle = resolvedSurfaceStyle()
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

    private func resolvedSurfaceStyle() -> ButtonSurfaceStyle {
        if role == .destructive, resolvedButtonStyle == .automatic {
            return .destructive
        }

        return resolvedButtonStyle == .automatic ? style : resolvedButtonStyle.surfaceStyle
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
public struct Toggle: View {
    public typealias Body = Never

    private static let defaultTintColor = Color(red: 0.24, green: 0.62, blue: 1.0, alpha: 1.0)

    private let isOn: Binding<Bool>
    private let label: [AnyView]
    private var isEnabled: Bool
    private var tintColor: Color?
    private var offColor: Color

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
    }

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> [AnyView]) {
        self.isOn = isOn
        self.label = label()
        self.isEnabled = true
        self.tintColor = nil
        self.offColor = Color(red: 0.31, green: 0.35, blue: 0.42, alpha: 1.0)
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

            guard !label.isEmpty else {
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

    public func tint(_ color: Color) -> Toggle {
        var copy = self
        copy.tintColor = color
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

    public func tint(_ color: Color) -> Slider {
        var copy = self
        copy.tintColor = color
        return copy
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

    public func tint(_ color: Color) -> ProgressView {
        var copy = self
        copy.tintColor = color
        return copy
    }
}

@MainActor
public struct Picker<SelectionValue: Hashable>: View {
    public typealias Body = Never

    private let title: String
    private let selection: Binding<SelectionValue>
    private let content: [AnyView]
    private var isEnabled: Bool

    public init(_ title: String = "", selection: Binding<SelectionValue>, @ViewBuilder content: () -> [AnyView]) {
        self.title = title
        self.selection = selection
        self.content = content()
        self.isEnabled = true
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

            guard !title.isEmpty else {
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

private func resolvedSymbolIcon(for systemName: String) -> SymbolIcon {
    switch systemName {
    case "magnifyingglass":
        return .search
    case "folder":
        return .folder
    case "gearshape", "gearshape.fill":
        return .settings
    case "bolt", "bolt.fill":
        return .lightning
    case "rectangle.3.group", "square.grid.3x1.folder.badge.plus":
        return .layout
    case "keyboard":
        return .keyboard
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
    default:
        return .sparkle
    }
}
