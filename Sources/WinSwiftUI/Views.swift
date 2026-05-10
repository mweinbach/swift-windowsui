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

public enum RoundedCornerStyle: Sendable, Equatable {
    case circular
    case continuous
}

@MainActor
public struct Rectangle: View {
    public typealias Body = Never

    private var fillColor: Color?
    private var strokeColor: Color
    private var lineWidth: Double

    public init() {
        self.fillColor = nil
        self.strokeColor = .clear
        self.lineWidth = 0
    }

    public var body: Never {
        fatalError("Rectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillColor: fillColor ?? context.foregroundColor,
            strokeColor: strokeColor,
            lineWidth: lineWidth,
            cornerRadius: 0
        )
    }

    public func fill(_ color: Color) -> Rectangle {
        var copy = self
        copy.fillColor = color
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        var copy = self
        copy.fillColor = .clear
        copy.strokeColor = color
        copy.lineWidth = max(0, lineWidth)
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        stroke(color, lineWidth: lineWidth)
    }
}

@MainActor
public struct RoundedRectangle: View {
    public typealias Body = Never

    private let cornerRadius: Double
    private let style: RoundedCornerStyle
    private var fillColor: Color?
    private var strokeColor: Color
    private var lineWidth: Double

    public init(cornerRadius: Double, style: RoundedCornerStyle = .circular) {
        self.cornerRadius = max(0, cornerRadius)
        self.style = style
        self.fillColor = nil
        self.strokeColor = .clear
        self.lineWidth = 0
    }

    public var body: Never {
        fatalError("RoundedRectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillColor: fillColor ?? context.foregroundColor,
            strokeColor: strokeColor,
            lineWidth: lineWidth,
            cornerRadius: cornerRadius
        )
    }

    public func fill(_ color: Color) -> RoundedRectangle {
        var copy = self
        copy.fillColor = color
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        var copy = self
        copy.fillColor = .clear
        copy.strokeColor = color
        copy.lineWidth = max(0, lineWidth)
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(color, lineWidth: lineWidth)
    }
}

@MainActor
public struct Capsule: View {
    public typealias Body = Never

    private let style: RoundedCornerStyle
    private var fillColor: Color?
    private var strokeColor: Color
    private var lineWidth: Double

    public init(style: RoundedCornerStyle = .circular) {
        self.style = style
        self.fillColor = nil
        self.strokeColor = .clear
        self.lineWidth = 0
    }

    public var body: Never {
        fatalError("Capsule has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillColor: fillColor ?? context.foregroundColor,
            strokeColor: strokeColor,
            lineWidth: lineWidth
        )
    }

    public func fill(_ color: Color) -> Capsule {
        var copy = self
        copy.fillColor = color
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Capsule {
        var copy = self
        copy.fillColor = .clear
        copy.strokeColor = color
        copy.lineWidth = max(0, lineWidth)
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Capsule {
        stroke(color, lineWidth: lineWidth)
    }
}

extension Rectangle: Shape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .rectangle
    }
}

extension RoundedRectangle: Shape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .roundedRectangle(cornerRadius)
    }
}

extension Capsule: Shape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}

@MainActor
private func shapeComponent(
    fillColor: Color,
    strokeColor: Color,
    lineWidth: Double,
    cornerRadius: Double
) -> Component {
    Component { _ in
        Controls.panel(
            backgroundColor: fillColor,
            borderColor: strokeColor,
            borderWidth: lineWidth,
            cornerRadius: cornerRadius,
            isHitTestVisible: false
        )
    }
}

@MainActor
private func capsuleComponent(
    fillColor: Color,
    strokeColor: Color,
    lineWidth: Double
) -> Component {
    Component { _ in
        let node = Controls.panel(
            backgroundColor: fillColor,
            borderColor: strokeColor,
            borderWidth: lineWidth,
            isHitTestVisible: false
        )
        node.onLayout = { [weak node] bounds in
            let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
            if node?.cornerRadius != radius {
                node?.cornerRadius = radius
            }
        }
        return node
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
public struct NavigationStack: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder root: () -> [AnyView]) {
        self.content = root()
    }

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> [AnyView]) {
        _ = path
        self.content = root()
    }

    public init<Data>(
        path: Binding<Data>,
        @ViewBuilder root: () -> [AnyView]
    ) where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection, Data.Element: Hashable {
        _ = path
        self.content = root()
    }

    public var body: Never {
        fatalError("NavigationStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}

@MainActor
public struct NavigationView: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("NavigationView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}

@MainActor
public struct NavigationSplitView: View {
    public typealias Body = Never

    private let columns: [[AnyView]]
    private let columnVisibility: Binding<NavigationSplitViewVisibility>?

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), detail()]
        self.columnVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), detail()]
        self.columnVisibility = columnVisibility
    }

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), content(), detail()]
        self.columnVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), content(), detail()]
        self.columnVisibility = columnVisibility
    }

    public var body: Never {
        fatalError("NavigationSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = columnVisibility
        let columnComponents = columns.map { column in
            composeComponent(
                from: column,
                context: context.withStackAxis(.vertical),
                fallbackLayout: .stack(.vertical(alignment: .stretch))
            )
        }

        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .horizontal(spacing: 0, alignment: .stretch),
                isHitTestVisible: false,
                children: columnComponents.map { $0.makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct NavigationLink: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let destination: [AnyView]
    private let value: AnyHashable?

    public init<Destination: View>(
        destination: Destination,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
    }

    public init<Destination: View>(
        _ title: String,
        destination: Destination
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = [AnyView(destination)]
        self.value = nil
    }

    public init<Destination: View>(
        _ titleKey: LocalizedStringKey,
        destination: Destination
    ) {
        self.init(titleKey.resolvedString, destination: destination)
    }

    public init<Value: Hashable>(
        value: Value,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = []
        self.value = AnyHashable(value)
    }

    public init<Value: Hashable>(
        _ title: String,
        value: Value
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = []
        self.value = AnyHashable(value)
    }

    public init<Value: Hashable>(
        _ titleKey: LocalizedStringKey,
        value: Value
    ) {
        self.init(titleKey.resolvedString, value: value)
    }

    public var body: Never {
        fatalError("NavigationLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        _ = destination
        _ = value
        return composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )
    }
}

@MainActor
public struct TabView: View {
    public typealias Body = Never

    private let content: [AnyView]
    private let selectedTag: (@MainActor () -> AnyHashable?)?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.selectedTag = nil
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectedTag = {
            AnyHashable(selection.wrappedValue)
        }
    }

    public var body: Never {
        fatalError("TabView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let selectedContent = selectedPage()
        return composeComponent(
            from: selectedContent,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }

    private func selectedPage() -> [AnyView] {
        guard !content.isEmpty else {
            return []
        }

        guard let selectedTag = selectedTag?(),
              let selectedIndex = content.firstIndex(where: { $0.selectionTag == selectedTag }) else {
            return [content[0]]
        }

        return [content[selectedIndex]]
    }
}

@MainActor
public struct ForEach<Data: RandomAccessCollection, ID: Hashable>: View {
    public typealias Body = Never

    let contentViews: [AnyView]

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: (Data.Element) -> [AnyView]) {
        self.contentViews = Self.buildContentViews(data: data, id: id, content: content)
    }

    public var body: Never {
        fatalError("ForEach has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: contentViews, context: context)
    }

    private static func buildContentViews(
        data: Data,
        id: KeyPath<Data.Element, ID>,
        content: (Data.Element) -> [AnyView]
    ) -> [AnyView] {
        var views: [AnyView] = []
        for element in data {
            let elementID = String(describing: element[keyPath: id])
            let elementViews = content(element)
            for (index, view) in elementViews.enumerated() {
                views.append(AnyView(view.id("\(elementID)#\(index)")))
            }
        }
        return views
    }
}

public extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    init(_ data: Data, @ViewBuilder content: (Data.Element) -> [AnyView]) {
        self.init(data, id: \.id, content: content)
    }
}

public extension ForEach where Data == Range<Int>, ID == Int {
    init(_ data: Range<Int>, @ViewBuilder content: (Int) -> [AnyView]) {
        self.init(data, id: \.self, content: content)
    }
}

public extension ForEach where Data == ClosedRange<Int>, ID == Int {
    init(_ data: ClosedRange<Int>, @ViewBuilder content: (Int) -> [AnyView]) {
        self.init(data, id: \.self, content: content)
    }
}

@MainActor
public struct Text: View {
    public typealias Body = Never

    private let content: String
    private var color: Color?
    private var font: Font?
    private var alignment: TextAlignment?
    private var lineLimit: Int??

    public init(_ content: String) {
        self.content = content
        self.color = nil
        self.font = nil
        self.alignment = nil
        self.lineLimit = nil
    }

    public init(_ key: LocalizedStringKey) {
        self.init(key.resolvedString)
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
        let resolvedColor = color ?? context.foregroundColor
        let inheritedFont = context.fontWeight.map { context.font.weight($0) } ?? context.font
        let resolvedFont = font ?? inheritedFont
        let resolvedAlignment = alignment ?? context.textAlignment
        let resolvedLineLimit: Int?
        if let lineLimit {
            resolvedLineLimit = lineLimit
        } else {
            resolvedLineLimit = context.lineLimit
        }

        return Component { _ in
            Controls.label(
                content,
                color: resolvedColor,
                scale: resolvedFont.resolvedScale,
                weight: resolvedFont.weight.textWeight,
                fontFamily: resolvedFont.resolvedFamily,
                nativeFontSize: resolvedFont.resolvedNativeTextSize,
                alignment: resolvedAlignment.horizontalAlignment.textAlignment,
                lineBreakMode: resolvedLineBreakMode(lineLimit: resolvedLineLimit),
                maximumNumberOfLines: resolvedLineLimit
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

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        guard let weight else {
            return self
        }

        var copy = self
        let baseFont = copy.font ?? .system(size: 2)
        copy.font = baseFont.weight(weight)
        return copy
    }

    public func bold() -> Text {
        fontWeight(.bold)
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ lineLimit: Int?) -> Text {
        var copy = self
        copy.lineLimit = .some(lineLimit)
        return copy
    }

    private func resolvedLineBreakMode(lineLimit: Int?) -> TextLineBreakMode {
        if let lineLimit, lineLimit == 1 {
            return .truncateTail
        }

        return .wrap
    }
}

@MainActor
public struct Image: View {
    public typealias Body = Never

    public enum ResizingMode: Sendable {
        case tile
        case stretch
    }

    private let systemName: String
    private var color: Color?
    private var font: Font
    private var alignment: TextAlignment

    public init(systemName: String) {
        self.systemName = systemName
        self.color = nil
        self.font = .system(size: 1.9)
        self.alignment = .center
    }

    public var body: Never {
        fatalError("Image has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let symbol = resolvedSymbolIcon(for: systemName)
        let resolvedColor = color ?? context.foregroundColor
        return Component { _ in
            Controls.icon(
                symbol,
                color: resolvedColor,
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

    public func resizable(capInsets: EdgeInsets = .zero, resizingMode: ResizingMode = .stretch) -> Image {
        self
    }
}

@MainActor
public struct Label: View {
    public typealias Body = Never

    private let title: [AnyView]
    private let icon: [AnyView]
    private var color: Color?
    private var font: Font
    private var spacing: Double

    public init(_ title: String, systemImage: String) {
        self.title = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(systemName: systemImage))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.init(titleKey.resolvedString, systemImage: systemImage)
    }

    public init(@ViewBuilder title: () -> [AnyView], @ViewBuilder icon: () -> [AnyView]) {
        self.title = title()
        self.icon = icon()
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public var body: Never {
        fatalError("Label has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let resolvedColor = color ?? context.foregroundColor
        let labelContext = context
            .withForegroundColor(resolvedColor)
            .withFont(font)
            .withTextAlignment(.leading)
            .withLineLimit(1)
        return HStack(spacing: spacing) {
            icon
            title
        }
        .makeComponent(context: labelContext)
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

    public init() {}

    public var body: Never {
        fatalError("Divider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let isVertical = context.stackAxis == .horizontal
        return Component { _ in
            Controls.panel(
                preferredSize: Size(
                    width: isVertical ? 1 : 16,
                    height: isVertical ? 16 : 1
                ),
                backgroundColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
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
        Component { runtime in
            let childContext = context.withStackAxis(.vertical)
            return Controls.stackPanel(
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
        Component { runtime in
            let childContext = context.withStackAxis(.horizontal)
            return Controls.stackPanel(
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
        return Component { runtime in
            let childContext = context.withStackAxis(.vertical)
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
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
        return Component { runtime in
            let childContext = context.withStackAxis(.horizontal)
            return Controls.stackPanel(
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
        Component { runtime in
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
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
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

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = ForEach(data, id: id, content: rowContent).contentViews
    }

    public var body: Never {
        fatalError("List has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.scrollPanel(
                axis: .vertical,
                stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .stretch),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }
}

public extension List {
    init<Data: RandomAccessCollection>(
        _ data: Data,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.init(data, id: \.id, rowContent: rowContent)
    }
}

@MainActor
public struct Form: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Form has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            Controls.stackPanel(
                stackLayout: .vertical(spacing: 12, padding: EdgeInsets.all(12), alignment: .stretch),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct Section: View {
    public typealias Body = Never

    private let header: [AnyView]
    private let footer: [AnyView]
    private let style: SectionStyle
    private let content: [AnyView]

    public init(_ title: String, style: SectionStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.header = [
            AnyView(
                Text(title)
                    .foregroundColor(style.headerColor)
                    .font(style.headerFont)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.footer = []
        self.style = style
        self.content = content()
    }

    public init(_ titleKey: LocalizedStringKey, style: SectionStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, style: style, content: content)
    }

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.header = []
        self.footer = []
        self.style = .default
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = []
        self.style = .default
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView],
        @ViewBuilder footer: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = footer()
        self.style = .default
        self.content = content()
    }

    public var body: Never {
        fatalError("Section has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let headerContext = context
                .withForegroundColor(style.headerColor)
                .withFont(style.headerFont)
                .withTextAlignment(.leading)
                .withLineLimit(1)
            let footerContext = context
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.leading)

            let children =
                header.map { $0.makeComponent(context: headerContext).makeNode(runtime: runtime) } +
                content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) } +
                footer.map { $0.makeComponent(context: footerContext).makeNode(runtime: runtime) }

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
                children: children
            )

            if let scrollAxis = style.scrollAxis?.scrollAxis {
                node.scrollAxis = scrollAxis
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
}

@MainActor
public struct GroupBox: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.label = []
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.content = content()
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .font(.system(size: 1.5, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public var body: Never {
        fatalError("GroupBox has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let views = label + content
        return Component { runtime in
            Controls.panel(
                backgroundColor: Color(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.54),
                borderColor: Color(red: 0.78, green: 0.86, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 12,
                layoutMode: .stack(.vertical(spacing: 8, padding: .all(12), alignment: .stretch)),
                isHitTestVisible: false,
                children: views.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct DisclosureGroup: View {
    public typealias Body = Never

    private final class ExpansionState {
        var isExpanded = false
    }

    private let isExpanded: Binding<Bool>?
    private let expansionState: ExpansionState
    private let label: [AnyView]
    private let content: [AnyView]

    public init(
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.isExpanded = isExpanded
        self.expansionState = ExpansionState()
        self.label = label()
        self.content = content()
    }

    public init(
        _ title: String,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, isExpanded: isExpanded, content: content)
    }

    public var body: Never {
        fatalError("DisclosureGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let binding = isExpanded
        let fallbackState = expansionState
        let contentViews = content
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let contentComponent = composeComponent(
            from: contentViews,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 6, alignment: .stretch)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let isOpen = binding?.wrappedValue ?? fallbackState.isExpanded
            let chevronNode = Controls.label(
                isOpen ? "V" : ">",
                preferredSize: Size(width: 18, height: 24),
                color: context.foregroundColor,
                scale: 1.3,
                weight: .semibold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let headerContent = Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(spacing: 8, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center),
                isHitTestVisible: false,
                children: [chevronNode, labelNode]
            )
            let headerButton = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                clipsToBounds: false,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                action: {
                    if let binding {
                        binding.wrappedValue.toggle()
                    } else {
                        fallbackState.isExpanded.toggle()
                    }
                    context.invalidate()
                },
                children: [headerContent]
            )

            var children: [ViewNode] = [headerButton]
            if isOpen {
                let contentNode = contentComponent.makeNode(runtime: runtime)
                let insetContent = Controls.stackPanel(
                    stackLayout: .vertical(padding: EdgeInsets(top: 2, leading: 34, bottom: 2, trailing: 0), alignment: .stretch),
                    isHitTestVisible: false,
                    children: [contentNode]
                )
                children.append(insetContent)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 4, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}

@MainActor
public struct Menu: View {
    public typealias Body = Never

    private final class MenuState {
        var isOpen = false
    }

    private let state = MenuState()
    private let label: [AnyView]
    private let content: [AnyView]

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public var body: Never {
        fatalError("Menu has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let menuState = state
        let menuItems = content
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let disclosureNode = Controls.label(
                menuState.isOpen ? "V" : ">",
                preferredSize: Size(width: 18, height: 24),
                color: context.foregroundColor,
                scale: 1.2,
                weight: .semibold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let headerContent = Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(spacing: 8, padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10), alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, disclosureNode]
            )
            let menuButton = Controls.button(
                runtime: runtime,
                cornerRadius: ButtonSurfaceStyle.default.cornerRadius,
                palette: ButtonSurfaceStyle.default.palette,
                chrome: ButtonSurfaceStyle.default.chrome,
                clipsToBounds: ButtonSurfaceStyle.default.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                action: {
                    menuState.isOpen.toggle()
                    context.invalidate()
                },
                children: [headerContent]
            )

            var children: [ViewNode] = [menuButton]
            if menuState.isOpen {
                let itemContext = context.withButtonStyle(.plain)
                let itemNodes = menuItems.map { $0.makeComponent(context: itemContext).makeNode(runtime: runtime) }
                let menuPanel = Controls.stackPanel(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.96),
                    borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderWidth: 1,
                    shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.28),
                    shadowOffset: Point(x: 0, y: 10),
                    shadowSpread: 8,
                    cornerRadius: 10,
                    stackLayout: .vertical(spacing: 2, padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), alignment: .stretch),
                    isHitTestVisible: false,
                    children: itemNodes
                )
                children.append(menuPanel)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 4, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}

@MainActor
public struct TextField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(titleKey.resolvedString, text: text)
    }

    public var body: Never {
        fatalError("TextField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: title,
            text: text,
            isSecure: false,
            allowsNewlines: false,
            preferredSize: Size(width: 220, height: 36),
            context: context
        )
    }
}

@MainActor
public struct SecureField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>

    public init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(titleKey.resolvedString, text: text)
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: title,
            text: text,
            isSecure: true,
            allowsNewlines: false,
            preferredSize: Size(width: 220, height: 36),
            context: context
        )
    }
}

@MainActor
public struct TextEditor: View {
    public typealias Body = Never

    private let text: Binding<String>

    public init(text: Binding<String>) {
        self.text = text
    }

    public var body: Never {
        fatalError("TextEditor has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: nil,
            text: text,
            isSecure: false,
            allowsNewlines: true,
            preferredSize: Size(width: 260, height: 120),
            context: context
        )
    }
}

@MainActor
private func textInputComponent(
    title: String?,
    text: Binding<String>,
    isSecure: Bool,
    allowsNewlines: Bool,
    preferredSize: Size,
    context: ViewBuildContext
) -> Component {
    let binding = text
    let placeholder = title
    return Component { runtime in
        let currentText = binding.wrappedValue
        let isShowingPlaceholder = currentText.isEmpty
        let displayText = isSecure && !isShowingPlaceholder ? String(repeating: "*", count: currentText.count) : currentText
        let textColor: Color
        if !context.isEnabled {
            textColor = Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.78)
        } else if isShowingPlaceholder {
            textColor = Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 0.84)
        } else {
            textColor = context.foregroundColor
        }

        let labelNode = Controls.label(
            isShowingPlaceholder ? (placeholder ?? "") : displayText,
            color: textColor,
            scale: context.font.resolvedScale,
            weight: (context.fontWeight ?? context.font.weight).textWeight,
            fontFamily: context.font.resolvedFamily,
            nativeFontSize: context.font.resolvedNativeTextSize,
            alignment: context.textAlignment.horizontalAlignment.textAlignment,
            insets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            lineBreakMode: allowsNewlines ? .wrap : .truncateTail,
            maximumNumberOfLines: allowsNewlines ? nil : 1
        )
        let node = Controls.stackPanel(
            preferredSize: preferredSize,
            backgroundColor: context.isEnabled
                ? Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
                : Color(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.58),
            borderColor: context.isEnabled
                ? Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
                : Color(red: 0.45, green: 0.48, blue: 0.52, alpha: 0.20),
            borderWidth: 1,
            cornerRadius: 8,
            stackLayout: .vertical(padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10), alignment: .stretch),
            isHitTestVisible: context.isEnabled,
            children: [labelNode]
        )

        guard context.isEnabled else {
            return node
        }

        node.isFocusable = true
        node.onFocusEnter = { [weak node] in
            node?.borderColor = context.tint
            node?.outlineColor = context.tint.opacity(0.28)
            node?.outlineWidth = 2
        }
        node.onFocusExit = { [weak node] in
            node?.borderColor = Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
            node?.outlineColor = .clear
            node?.outlineWidth = 0
        }
        node.onKeyDown = { event in
            if event.key == .backspace {
                guard !binding.wrappedValue.isEmpty else {
                    return
                }

                binding.wrappedValue.removeLast()
                context.invalidate()
                return
            }

            guard let character = textFieldInsertedCharacter(for: event, allowsNewlines: allowsNewlines) else {
                return
            }

            binding.wrappedValue.append(contentsOf: character)
            context.invalidate()
        }

        return node
    }
}

@MainActor
public struct Toggle: View {
    public typealias Body = Never

    private let isOn: Binding<Bool>
    private let label: [AnyView]

    public init(_ title: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.6, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
    }

    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(titleKey.resolvedString, isOn: isOn)
    }

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> [AnyView]) {
        self.isOn = isOn
        self.label = label()
    }

    public var body: Never {
        fatalError("Toggle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let binding = isOn

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let toggleNode = Controls.toggle(
                runtime: runtime,
                isOn: binding.wrappedValue,
                isEnabled: context.isEnabled,
                onColor: context.tint,
                onToggle: { newValue in
                    binding.wrappedValue = newValue
                    context.invalidate()
                }
            )

            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 10, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, toggleNode]
            )
        }
    }
}

@MainActor
public struct Picker<SelectionValue: Hashable>: View {
    public typealias Body = Never

    private let selection: Binding<SelectionValue>
    private let label: [AnyView]
    private let content: [AnyView]

    private struct Option {
        var value: SelectionValue?
        var node: ViewNode
    }

    public init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.6, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.content = content()
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, selection: selection, content: content)
    }

    public init<Label: View>(
        selection: Binding<SelectionValue>,
        label: Label,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = [AnyView(label)]
        self.content = content()
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
        self.content = content()
    }

    public var body: Never {
        fatalError("Picker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let selection = selection
        let labelViews = label
        let contentViews = content
        let labelComponent = composeComponent(
            from: labelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let selectedValue = selection.wrappedValue
            let selectedAnyValue = AnyHashable(selectedValue)
            let options: [Option] = contentViews.enumerated().map { index, option in
                let representedValue = Self.selectionValue(for: option, fallbackIndex: index)
                let optionNode = option.makeComponent(context: context).makeNode(runtime: runtime)
                return Option(value: representedValue, node: optionNode)
            }

            let pickerNode: ViewNode
            switch context.pickerStyle.kind {
            case .automatic, .segmented:
                pickerNode = Self.segmentedPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .menu:
                pickerNode = Self.menuPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    options: options
                )
            }

            guard !labelViews.isEmpty else {
                return pickerNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [labelNode, pickerNode]
            )
        }
    }

    private static func selectionValue(for option: AnyView, fallbackIndex: Int) -> SelectionValue? {
        if let tagValue = option.selectionTag?.base as? SelectionValue {
            return tagValue
        }
        return fallbackIndex as? SelectionValue
    }

    private static func segmentedPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedValue: SelectionValue,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette

            return Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.45) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderHoveredColor: isSelected ? context.tint.opacity(0.62) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
                    borderFocusedColor: isSelected ? context.tint.opacity(0.76) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.26),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(.vertical(
                    padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                    alignment: .center,
                    mainAlignment: .center
                )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [option.node]
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.90),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func menuPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedValue: SelectionValue,
        options: [Option]
    ) -> ViewNode {
        let titles = options.enumerated().map { index, option in
            firstText(in: option.node) ?? "OPTION \(index + 1)"
        }
        let selectedIndex = options.firstIndex { $0.value == selectedValue } ?? 0
        let hasSelectableOption = options.contains { $0.value != nil }

        return Controls.dropdown(
            runtime: runtime,
            options: titles,
            selectedIndex: selectedIndex,
            isEnabled: context.isEnabled && hasSelectableOption,
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
    }

    private static func firstText(in node: ViewNode) -> String? {
        if let text = node.text {
            return text
        }

        for child in node.children {
            if let text = firstText(in: child) {
                return text
            }
        }

        return nil
    }

    private static func selectedPalette(tint: Color) -> SurfacePalette {
        SurfacePalette(
            idle: tint.opacity(0.82),
            hovered: tint.opacity(0.90),
            focused: tint.opacity(0.96),
            pressed: tint,
            activated: tint
        )
    }

    private static var unselectedPalette: SurfacePalette {
        SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.78),
            hovered: Color(red: 0.22, green: 0.29, blue: 0.39, alpha: 0.86),
            focused: Color(red: 0.26, green: 0.35, blue: 0.47, alpha: 0.90),
            pressed: Color(red: 0.31, green: 0.42, blue: 0.56, alpha: 0.96),
            activated: Color(red: 0.36, green: 0.48, blue: 0.63, alpha: 0.96)
        )
    }
}

@MainActor
public struct Stepper: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let canDecrement: @MainActor () -> Bool
    private let canIncrement: @MainActor () -> Bool
    private let decrement: @MainActor () -> Void
    private let increment: @MainActor () -> Void

    public init(
        _ title: String,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(titleKey.resolvedString, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        let resolvedStep = Self.resolvedDoubleStep(step)
        self.label = label()
        self.canDecrement = {
            value.wrappedValue > bounds.lowerBound
        }
        self.canIncrement = {
            value.wrappedValue < bounds.upperBound
        }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedDouble(value.wrappedValue, by: -resolvedStep, in: bounds)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedDouble(value.wrappedValue, by: resolvedStep, in: bounds)
            onEditingChanged(false)
        }
    }

    public init(
        _ title: String,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(titleKey.resolvedString, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        let resolvedStep = max(1, step)
        self.label = label()
        self.canDecrement = {
            value.wrappedValue > bounds.lowerBound
        }
        self.canIncrement = {
            value.wrappedValue < bounds.upperBound
        }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedInt(value.wrappedValue, by: -resolvedStep, in: bounds)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedInt(value.wrappedValue, by: resolvedStep, in: bounds)
            onEditingChanged(false)
        }
    }

    public var body: Never {
        fatalError("Stepper has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let canDecrement = canDecrement
        let canIncrement = canIncrement
        let decrement = decrement
        let increment = increment

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let decrementNode = Self.controlButton(
                runtime: runtime,
                title: "-",
                isEnabled: context.isEnabled && canDecrement(),
                action: {
                    decrement()
                    context.invalidate()
                }
            )
            let incrementNode = Self.controlButton(
                runtime: runtime,
                title: "+",
                isEnabled: context.isEnabled && canIncrement(),
                action: {
                    increment()
                    context.invalidate()
                }
            )

            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, decrementNode, incrementNode]
            )
        }
    }

    private static func controlButton(
        runtime: RetainedViewRuntime,
        title: String,
        isEnabled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> ViewNode {
        let surfaceStyle = ButtonSurfaceStyle.default
        let titleNode = Controls.label(
            title,
            color: isEnabled ? .white : surfaceStyle.palette.disabledForeground,
            scale: 1.6,
            weight: .bold,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        return Controls.button(
            runtime: runtime,
            preferredSize: Size(width: 34, height: 30),
            cornerRadius: 12,
            palette: surfaceStyle.palette,
            chrome: surfaceStyle.chrome,
            clipsToBounds: surfaceStyle.clipsToBounds,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: isEnabled,
            animation: surfaceStyle.animation,
            action: action,
            children: [titleNode]
        )
    }

    private static func resolvedDoubleStep(_ step: Double) -> Double {
        step.isFinite && step > 0 ? step : 1
    }

    private static func steppedDouble(_ value: Double, by delta: Double, in bounds: ClosedRange<Double>) -> Double {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        let candidate = clampedValue + delta
        guard candidate.isFinite else {
            return delta > 0 ? bounds.upperBound : bounds.lowerBound
        }
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }

    private static func steppedInt(_ value: Int, by delta: Int, in bounds: ClosedRange<Int>) -> Int {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        if delta >= 0 {
            let (candidate, overflow) = clampedValue.addingReportingOverflow(delta)
            guard !overflow else {
                return bounds.upperBound
            }
            return min(max(candidate, bounds.lowerBound), bounds.upperBound)
        }

        let (candidate, overflow) = clampedValue.addingReportingOverflow(delta)
        guard !overflow else {
            return bounds.lowerBound
        }
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }
}

@MainActor
public struct Slider: View {
    public typealias Body = Never

    private let value: Binding<Double>
    private let bounds: ClosedRange<Double>
    private let step: Double?
    private let onEditingChanged: @MainActor (Bool) -> Void
    private let label: [AnyView]
    private let minimumValueLabel: [AnyView]
    private let maximumValueLabel: [AnyView]

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init<MinimumValueLabel: View, MaximumValueLabel: View>(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        minimumValueLabel: MinimumValueLabel,
        maximumValueLabel: MaximumValueLabel,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = [AnyView(minimumValueLabel)]
        self.maximumValueLabel = [AnyView(maximumValueLabel)]
    }

    public init<MinimumValueLabel: View, MaximumValueLabel: View>(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        minimumValueLabel: MinimumValueLabel,
        maximumValueLabel: MaximumValueLabel,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = [AnyView(minimumValueLabel)]
        self.maximumValueLabel = [AnyView(maximumValueLabel)]
    }

    public var body: Never {
        fatalError("Slider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let binding = value
        let range = bounds
        let step = step
        let onEditingChanged = onEditingChanged
        let labelViews = label
        let minimumLabelViews = minimumValueLabel
        let maximumLabelViews = maximumValueLabel
        let labelComponent = composeComponent(
            from: labelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let minimumLabelComponent = composeComponent(
            from: minimumLabelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let maximumLabelComponent = composeComponent(
            from: maximumLabelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let sliderNode = Controls.slider(
                runtime: runtime,
                value: binding.wrappedValue,
                range: range,
                isEnabled: context.isEnabled,
                layoutPriority: minimumLabelViews.isEmpty && maximumLabelViews.isEmpty ? 0 : 1,
                filledColor: context.tint,
                onValueChanged: { newValue in
                    binding.wrappedValue = Self.snappedValue(newValue, in: range, step: step)
                    context.invalidate()
                },
                onEditingChanged: { isEditing in
                    onEditingChanged(isEditing)
                }
            )

            guard !labelViews.isEmpty || !minimumLabelViews.isEmpty || !maximumLabelViews.isEmpty else {
                return sliderNode
            }

            var rowChildren: [ViewNode] = []
            if !minimumLabelViews.isEmpty {
                rowChildren.append(minimumLabelComponent.makeNode(runtime: runtime))
            }
            rowChildren.append(sliderNode)
            if !maximumLabelViews.isEmpty {
                rowChildren.append(maximumLabelComponent.makeNode(runtime: runtime))
            }

            let rowNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: rowChildren
            )

            guard !labelViews.isEmpty else {
                return rowNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 6, alignment: .stretch),
                isHitTestVisible: false,
                children: [labelNode, rowNode]
            )
        }
    }

    private static func snappedValue(_ value: Double, in bounds: ClosedRange<Double>, step: Double?) -> Double {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        guard let step, step.isFinite, step > 0 else {
            return clampedValue
        }
        if clampedValue <= bounds.lowerBound {
            return bounds.lowerBound
        }
        if clampedValue >= bounds.upperBound {
            return bounds.upperBound
        }

        let snapped = ((clampedValue - bounds.lowerBound) / step).rounded() * step + bounds.lowerBound
        return min(max(snapped, bounds.lowerBound), bounds.upperBound)
    }
}

@MainActor
public struct ProgressView: View {
    public typealias Body = Never

    private let value: Double?
    private let total: Double
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]

    public init(value: Double? = nil, total: Double = 1.0) {
        self.value = value
        self.total = total
        self.label = []
        self.currentValueLabel = []
    }

    public init(_ title: String, value: Double? = nil, total: Double = 1.0) {
        self.value = value
        self.total = total
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.5, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.currentValueLabel = []
    }

    public init(_ titleKey: LocalizedStringKey, value: Double? = nil, total: Double = 1.0) {
        self.init(titleKey.resolvedString, value: value, total: total)
    }

    public init(value: Double? = nil, total: Double = 1.0, @ViewBuilder label: () -> [AnyView]) {
        self.value = value
        self.total = total
        self.label = label()
        self.currentValueLabel = []
    }

    public init(
        value: Double? = nil,
        total: Double = 1.0,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.total = total
        self.label = label()
        self.currentValueLabel = currentValueLabel()
    }

    public var body: Never {
        fatalError("ProgressView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 0, alignment: .leading)),
            isHitTestVisible: false
        )
        let currentValueLabelComponent = composeComponent(
            from: currentValueLabel,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let progressNode = Controls.progressBar(value: value ?? 0, total: total, filledColor: context.tint)
            guard !label.isEmpty || !currentValueLabel.isEmpty else {
                return progressNode
            }

            guard !currentValueLabel.isEmpty else {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, progressNode]
                )
            }

            var headerChildren: [ViewNode] = []
            if !label.isEmpty {
                headerChildren.append(labelComponent.makeNode(runtime: runtime))
            }
            headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))

            let headerNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, progressNode]
            )
        }
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
    private var hasCustomSurfaceStyle: Bool

    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, systemImage: systemImage))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, systemImage: systemImage, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, action: action)
    }

    public init(_ title: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
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
        self.hasCustomSurfaceStyle = false
    }

    public init(_ title: String, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, systemImage: systemImage))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, systemImage: systemImage, role: role, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, role: role, action: action)
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
            let buttonStyle = resolvedButtonStyle == .automatic && !hasCustomSurfaceStyle ? context.buttonStyle : resolvedButtonStyle
            let surfaceStyle = resolvedSurfaceStyle(for: buttonStyle)
            return Controls.button(
                runtime: runtime,
                cornerRadius: surfaceStyle.cornerRadius,
                palette: surfaceStyle.palette,
                chrome: surfaceStyle.chrome,
                clipsToBounds: surfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                animation: surfaceStyle.animation,
                action: {
                    action()
                    context.invalidate()
                },
                children: [labelNode]
            )
        }
    }

    public func buttonSurface(_ style: ButtonSurfaceStyle) -> Button {
        var copy = self
        copy.style = style
        copy.resolvedButtonStyle = .automatic
        copy.hasCustomSurfaceStyle = true
        return copy
    }

    public func buttonStyle(_ style: ButtonStyle) -> Button {
        var copy = self
        copy.resolvedButtonStyle = style
        return copy
    }

    private func resolvedSurfaceStyle(for buttonStyle: ButtonStyle) -> ButtonSurfaceStyle {
        guard buttonStyle == .automatic else {
            return buttonStyle.surfaceStyle
        }

        if hasCustomSurfaceStyle {
            return style
        }

        switch role {
        case .destructive:
            return .destructive
        case .cancel, .none:
            return style
        }
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
    default:
        return .sparkle
    }
}

private func textFieldInsertedCharacter(for event: KeyboardEvent, allowsNewlines: Bool) -> String? {
    if event.key == .enter {
        return allowsNewlines ? "\n" : nil
    }

    if event.key == .space {
        return " "
    }

    switch event.keyCode {
    case 0x30...0x39:
        return String(UnicodeScalar(event.keyCode)!)
    case 0x41...0x5A:
        guard let scalar = UnicodeScalar(event.keyCode) else {
            return nil
        }

        let character = String(scalar)
        return event.modifiers.contains(.shift) ? character : character.lowercased()
    case 0xBA:
        return event.modifiers.contains(.shift) ? ":" : ";"
    case 0xBB:
        return event.modifiers.contains(.shift) ? "+" : "="
    case 0xBC:
        return event.modifiers.contains(.shift) ? "<" : ","
    case 0xBD:
        return event.modifiers.contains(.shift) ? "_" : "-"
    case 0xBE:
        return event.modifiers.contains(.shift) ? ">" : "."
    case 0xBF:
        return event.modifiers.contains(.shift) ? "?" : "/"
    default:
        return nil
    }
}
