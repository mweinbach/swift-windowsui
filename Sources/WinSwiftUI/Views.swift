import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsUI

private let defaultRetainedScrollIndicatorInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

private func retainedScrollAnchor(from anchor: UnitPoint?) -> RetainedScrollAnchor? {
    anchor.map { RetainedScrollAnchor(x: $0.x, y: $0.y) }
}

private func stackMainAlignment(from value: Double) -> StackMainAlignment {
    if value <= 0.25 {
        return .start
    }
    if value >= 0.75 {
        return .end
    }
    return .center
}

private func stackCrossAlignment(from value: Double) -> StackCrossAlignment {
    if value <= 0.25 {
        return .leading
    }
    if value >= 0.75 {
        return .trailing
    }
    return .center
}

public struct GeometryProxy {
    public let size: Size

    public init(size: Size) {
        self.size = size
    }
}

@MainActor
public struct ViewThatFits: View {
    public typealias Body = Never

    private let axes: Axis.Set
    private let content: [AnyView]

    public init(in axes: Axis.Set = .all, @ViewBuilder content: () -> [AnyView]) {
        self.axes = axes
        self.content = content()
    }

    public var body: Never {
        fatalError("ViewThatFits has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let axes = axes
        let components = content.map { $0.makeComponent(context: context) }

        return Component { runtime in
            guard !components.isEmpty else {
                return Controls.panel(preferredSize: .zero, isHitTestVisible: false)
            }

            let availableSize = context.canvasSize
            var fallbackNode: ViewNode?
            for component in components {
                let candidateNode = component.makeNode(runtime: runtime)
                fallbackNode = candidateNode
                let candidateSize = candidateNode.intrinsicContentSize()
                if Self.fits(candidateSize, in: availableSize, axes: axes) {
                    return candidateNode
                }
            }

            return fallbackNode ?? Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }

    private static func fits(_ candidateSize: Size, in availableSize: Size, axes: Axis.Set) -> Bool {
        if axes.contains(.horizontal), candidateSize.width > availableSize.width {
            return false
        }
        if axes.contains(.vertical), candidateSize.height > availableSize.height {
            return false
        }
        return true
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

    private var fillStyle: ForegroundStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Rectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: 0
        )
    }

    public func fill(_ color: Color) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(color)
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Rectangle {
        var copy = self
        copy.fillStyle = style
        return copy
    }

    public func fill(_ gradient: LinearGradient) -> Rectangle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Rectangle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(style: StrokeStyle) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Rectangle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Rectangle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Rectangle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Rectangle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Rectangle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(style: StrokeStyle) -> Rectangle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Rectangle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Rectangle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Rectangle {
        stroke(gradient, style: style)
    }
}

@MainActor
public struct RoundedRectangle: View {
    public typealias Body = Never

    private let cornerRadius: Double
    private let style: RoundedCornerStyle
    private var fillStyle: ForegroundStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(cornerRadius: Double, style: RoundedCornerStyle = .circular) {
        self.cornerRadius = max(0, cornerRadius)
        self.style = style
        self.fillStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("RoundedRectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: cornerRadius
        )
    }

    public func fill(_ color: Color) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(color)
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = style
        return copy
    }

    public func fill(_ gradient: LinearGradient) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(style: StrokeStyle) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(style: StrokeStyle) -> RoundedRectangle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> RoundedRectangle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> RoundedRectangle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> RoundedRectangle {
        stroke(gradient, style: style)
    }
}

@MainActor
public struct Capsule: View {
    public typealias Body = Never

    private let style: RoundedCornerStyle
    private var fillStyle: ForegroundStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(style: RoundedCornerStyle = .circular) {
        self.style = style
        self.fillStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Capsule has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func fill(_ color: Color) -> Capsule {
        var copy = self
        copy.fillStyle = .color(color)
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Capsule {
        var copy = self
        copy.fillStyle = style
        return copy
    }

    public func fill(_ gradient: LinearGradient) -> Capsule {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Capsule {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(style: StrokeStyle) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Capsule {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Capsule {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Capsule {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Capsule {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Capsule {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Capsule {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(style: StrokeStyle) -> Capsule {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Capsule {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Capsule {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Capsule {
        stroke(gradient, style: style)
    }
}

@MainActor
public struct Circle: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Circle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func fill(_ color: Color) -> Circle {
        var copy = self
        copy.fillStyle = .color(color)
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Circle {
        var copy = self
        copy.fillStyle = style
        return copy
    }

    public func fill(_ gradient: LinearGradient) -> Circle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Circle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(style: StrokeStyle) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Circle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Circle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Circle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Circle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Circle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Circle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(style: StrokeStyle) -> Circle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Circle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Circle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Circle {
        stroke(gradient, style: style)
    }
}

@MainActor
public struct Ellipse: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Ellipse has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func fill(_ color: Color) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(color)
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Ellipse {
        var copy = self
        copy.fillStyle = style
        return copy
    }

    public func fill(_ gradient: LinearGradient) -> Ellipse {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Ellipse {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(style: StrokeStyle) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Ellipse {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Ellipse {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Ellipse {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Ellipse {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Ellipse {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Ellipse {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(style: StrokeStyle) -> Ellipse {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Ellipse {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Ellipse {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Ellipse {
        stroke(gradient, style: style)
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

extension Circle: Shape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}

extension Ellipse: Shape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}

@MainActor
private func shapeComponent(
    fillStyle: ForegroundStyle,
    strokeStyle: ForegroundStyle,
    lineWidth: Double,
    strokeLineStyle: StrokeStyle?,
    cornerRadius: Double
) -> Component {
    Component { _ in
        let fill = resolvedFill(from: fillStyle)
        let stroke = resolvedFill(from: strokeStyle)
        let node = Controls.panel(
            backgroundColor: fill.color,
            backgroundGradient: fill.gradient,
            borderColor: stroke.color,
            borderGradient: stroke.gradient,
            borderWidth: lineWidth,
            cornerRadius: cornerRadius,
            isHitTestVisible: false
        )
        node.borderStrokeStyle = lineWidth > 0 ? strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: []) : nil
        return node
    }
}

@MainActor
private func capsuleComponent(
    fillStyle: ForegroundStyle,
    strokeStyle: ForegroundStyle,
    lineWidth: Double,
    strokeLineStyle: StrokeStyle?
) -> Component {
    Component { _ in
        let fill = resolvedFill(from: fillStyle)
        let stroke = resolvedFill(from: strokeStyle)
        let node = Controls.panel(
            backgroundColor: fill.color,
            backgroundGradient: fill.gradient,
            borderColor: stroke.color,
            borderGradient: stroke.gradient,
            borderWidth: lineWidth,
            isHitTestVisible: false
        )
        node.borderStrokeStyle = lineWidth > 0 ? strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: []) : nil
        node.onLayout = { [weak node] bounds in
            let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
            if node?.cornerRadius != radius {
                node?.cornerRadius = radius
            }
        }
        return node
    }
}

private extension StrokeStyle {
    var retainedShapeStrokeStyle: StrokeStyle {
        var copy = self
        copy.lineWidth = max(0, lineWidth)
        return copy
    }
}

private func resolvedFill(from style: ForegroundStyle) -> (color: Color, gradient: LinearGradient?) {
    switch style {
    case .color(let color):
        return (color, nil)
    case .linearGradient(let gradient):
        return (gradient.startColor, gradient)
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
private struct NavigationStackEntry {
    var destination: [AnyView]
    var onDismiss: (@MainActor () -> Void)?
}

@MainActor
private final class NavigationContainerState {
    var destinationStack: [NavigationStackEntry] = []
}

@MainActor
private struct NavigationPathBinding {
    var values: () -> [AnyHashable]
    var append: (AnyHashable) -> Bool
    var removeLast: () -> Void
}

@MainActor
public struct NavigationStack: View {
    public typealias Body = Never

    private let state: NavigationContainerState
    private let pathBinding: NavigationPathBinding?
    private let content: [AnyView]

    public init(@ViewBuilder root: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = nil
        self.content = root()
    }

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = NavigationPathBinding(
            values: {
                path.wrappedValue.anyElements
            },
            append: { value in
                var updatedPath = path.wrappedValue
                updatedPath.appendAnyHashable(value)
                path.wrappedValue = updatedPath
                return true
            },
            removeLast: {
                var updatedPath = path.wrappedValue
                updatedPath.removeLast()
                path.wrappedValue = updatedPath
            }
        )
        self.content = root()
    }

    public init<Data>(
        path: Binding<Data>,
        @ViewBuilder root: () -> [AnyView]
    ) where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection, Data.Element: Hashable {
        self.state = NavigationContainerState()
        self.pathBinding = NavigationPathBinding(
            values: {
                path.wrappedValue.map { AnyHashable($0) }
            },
            append: { value in
                guard let typedValue = value.base as? Data.Element else {
                    return false
                }

                var updatedPath = path.wrappedValue
                updatedPath.append(typedValue)
                path.wrappedValue = updatedPath
                return true
            },
            removeLast: {
                var updatedPath = path.wrappedValue
                if !updatedPath.isEmpty {
                    updatedPath.removeLast()
                    path.wrappedValue = updatedPath
                }
            }
        )
        self.content = root()
    }

    public var body: Never {
        fatalError("NavigationStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        navigationContainerComponent(
            from: content,
            state: state,
            pathBinding: pathBinding,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}

@MainActor
public struct NavigationView: View {
    public typealias Body = Never

    private let state: NavigationContainerState
    private let pathBinding: NavigationPathBinding?
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = nil
        self.content = content()
    }

    public var body: Never {
        fatalError("NavigationView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        navigationContainerComponent(
            from: content,
            state: state,
            pathBinding: pathBinding,
            context: context,
            navigationViewStyle: context.navigationViewStyle,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}

private struct RetainedNavigationViewChrome {
    var containerBackground: Color?
    var containerBorderColor: Color
    var containerBorderWidth: Double
    var containerCornerRadius: Double
    var headerBackground: Color
    var headerBorderColor: Color
    var headerBorderWidth: Double
    var headerCornerRadius: Double
    var spacing: Double
}

private func retainedNavigationViewChrome(for style: NavigationViewStyle?) -> RetainedNavigationViewChrome {
    let defaultChrome = RetainedNavigationViewChrome(
        containerBackground: nil,
        containerBorderColor: .clear,
        containerBorderWidth: 0,
        containerCornerRadius: 0,
        headerBackground: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.92),
        headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
        headerBorderWidth: 1,
        headerCornerRadius: 10,
        spacing: 10
    )

    guard let style else {
        return defaultChrome
    }

    switch style.kind {
    case .automatic:
        return defaultChrome
    case .stack:
        return RetainedNavigationViewChrome(
            containerBackground: nil,
            containerBorderColor: .clear,
            containerBorderWidth: 0,
            containerCornerRadius: 0,
            headerBackground: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.96),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
            headerBorderWidth: 1,
            headerCornerRadius: 10,
            spacing: 10
        )
    case .doubleColumn:
        return RetainedNavigationViewChrome(
            containerBackground: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.28),
            containerBorderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
            containerBorderWidth: 1,
            containerCornerRadius: 12,
            headerBackground: Color(red: 0.06, green: 0.09, blue: 0.14, alpha: 0.94),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            headerBorderWidth: 1,
            headerCornerRadius: 8,
            spacing: 12
        )
    case .columns:
        return RetainedNavigationViewChrome(
            containerBackground: Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.24),
            containerBorderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
            containerBorderWidth: 1,
            containerCornerRadius: 14,
            headerBackground: Color(red: 0.09, green: 0.13, blue: 0.19, alpha: 0.90),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            headerBorderWidth: 1,
            headerCornerRadius: 12,
            spacing: 12
        )
    }
}

@MainActor
private func navigationContainerComponent(
    from content: [AnyView],
    state: NavigationContainerState,
    pathBinding: NavigationPathBinding?,
    context: ViewBuildContext,
    navigationViewStyle: NavigationViewStyle? = nil,
    fallbackLayout: ViewLayoutMode
) -> Component {
    navigationContainerComponent(
        from: content,
        destinationStack: state.destinationStack,
        setDestinationStack: { state.destinationStack = $0 },
        pathBinding: pathBinding,
        context: context,
        navigationViewStyle: navigationViewStyle,
        fallbackLayout: fallbackLayout
    )
}

@MainActor
private func navigationContainerComponent(
    from content: [AnyView],
    destinationStack: [NavigationStackEntry],
    setDestinationStack: @escaping ([NavigationStackEntry]) -> Void,
    pathBinding: NavigationPathBinding?,
    context: ViewBuildContext,
    navigationViewStyle: NavigationViewStyle? = nil,
    fallbackLayout: ViewLayoutMode
) -> Component {
    let rootDestinationRegistrations = context.navigationDestinationRegistrations
        + navigationDestinations(in: content)
    let rootPresentedDestinations = context.navigationPresentedDestinations
        + navigationPresentedDestinations(in: content)
    let pathDestinationStack = resolvedNavigationStack(
        from: pathBinding?.values() ?? [],
        registrations: rootDestinationRegistrations
    )
    let activePresentation = activeNavigationPresentation(in: rootPresentedDestinations)
    let presentedDestination = activePresentation?.destination
    let pushedDestinationStack = destinationStack.map(\.destination)
    let combinedDestinationStack = pathDestinationStack + pushedDestinationStack + [presentedDestination].compactMap { $0 }
    let visibleContent = combinedDestinationStack.last ?? content
    let destinationRegistrations = rootDestinationRegistrations
        + navigationDestinations(in: visibleContent)

    func pushDestination(_ destination: [AnyView], onDismiss: (@MainActor () -> Void)? = nil) {
        guard !destination.isEmpty else {
            return
        }

        var updatedStack = destinationStack
        updatedStack.append(NavigationStackEntry(destination: destination, onDismiss: onDismiss))
        setDestinationStack(updatedStack)
        context.invalidate()
    }

    func dismissVisibleDestination() {
        var didDismiss = false
        if let activePresentation {
            activePresentation.dismiss()
            didDismiss = true
        } else if !destinationStack.isEmpty {
            var updatedStack = destinationStack
            let dismissed = updatedStack.popLast()
            setDestinationStack(updatedStack)
            dismissed?.onDismiss?()
            didDismiss = true
        } else if let pathBinding, !pathBinding.values().isEmpty {
            pathBinding.removeLast()
            didDismiss = true
        }

        if didDismiss {
            context.invalidate()
        }
    }

    let navigationContext = context
        .withEnvironmentValue(\.dismiss, DismissAction {
            dismissVisibleDestination()
        })
        .withEnvironmentValue(\.isPresented, !combinedDestinationStack.isEmpty)
        .withNavigationDestinationHandler { destination, onDismiss in
            pushDestination(destination, onDismiss: onDismiss)
        }
        .withNavigationValueHandler { value in
            guard let destination = resolveNavigationDestination(
                for: value,
                registrations: destinationRegistrations
            ) else {
                return false
            }

            if pathBinding?.append(value) == true {
                context.invalidate()
            } else {
                pushDestination(destination)
            }
            return true
        }
    let body = composeComponent(
        from: visibleContent,
        context: navigationContext,
        fallbackLayout: fallbackLayout
    )

    let title = navigationTitle(in: visibleContent) ?? navigationTitle(in: content)
    let hidesNavigationBar = navigationBarHidden(in: visibleContent) ?? navigationBarHidden(in: content) ?? false
    guard !hidesNavigationBar else {
        return body
    }

    let shouldShowChrome = title != nil || !combinedDestinationStack.isEmpty
    guard shouldShowChrome else {
        return body
    }

    let hidesBackButton = navigationBarBackButtonHidden(in: visibleContent) ?? false
    let displayMode = navigationTitleDisplayMode(in: visibleContent) ?? navigationTitleDisplayMode(in: content) ?? .automatic
    let titleFont: Font = displayMode == .inline
        ? .system(size: 2, weight: .semibold)
        : .system(size: 3, weight: .bold)
    let chrome = retainedNavigationViewChrome(for: navigationViewStyle)
    let titleContext = context
        .withForegroundColor(Color(red: 0.92, green: 0.96, blue: 1.0))
        .withFont(titleFont)

    let titleComponent = composeComponent(
        from: title ?? [AnyView(Text("BACK"))],
        context: titleContext,
        fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
    )

    return Component { runtime in
        let titleNode = titleComponent.makeNode(runtime: runtime)
        let bodyNode = body.makeNode(runtime: runtime)
        var headerChildren: [ViewNode] = []
        if !combinedDestinationStack.isEmpty && !hidesBackButton {
            let backLabel = Controls.label(
                "<",
                preferredSize: Size(width: 22, height: 26),
                color: Color(red: 0.92, green: 0.96, blue: 1.0),
                scale: 1.5,
                weight: .bold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let backButton = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                layoutMode: .stack(.vertical(
                    padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
                    alignment: .center,
                    mainAlignment: .center
                )),
                isEnabled: context.isEnabled,
                action: {
                    dismissVisibleDestination()
                },
                children: [backLabel]
            )
            headerChildren.append(backButton)
        }
        headerChildren.append(titleNode)

        let headerNode = Controls.stackPanel(
            backgroundColor: chrome.headerBackground,
            borderColor: chrome.headerBorderColor,
            borderWidth: chrome.headerBorderWidth,
            cornerRadius: chrome.headerCornerRadius,
            stackLayout: .horizontal(
                spacing: 8,
                padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: headerChildren
        )

        return Controls.stackPanel(
            backgroundColor: chrome.containerBackground,
            borderColor: chrome.containerBorderColor,
            borderWidth: chrome.containerBorderWidth,
            cornerRadius: chrome.containerCornerRadius,
            stackLayout: .vertical(spacing: chrome.spacing, alignment: .stretch),
            isHitTestVisible: false,
            children: [headerNode, bodyNode]
        )
    }
}

@MainActor
private func navigationTitle(in content: [AnyView]) -> [AnyView]? {
    content.lazy.compactMap(\.navigationTitle).first
}

@MainActor
private func navigationTitleDisplayMode(in content: [AnyView]) -> NavigationBarItem.TitleDisplayMode? {
    content.lazy.compactMap(\.navigationTitleDisplayMode).first
}

@MainActor
private func navigationBarBackButtonHidden(in content: [AnyView]) -> Bool? {
    content.lazy.compactMap(\.navigationBarBackButtonHidden).first
}

@MainActor
private func navigationBarHidden(in content: [AnyView]) -> Bool? {
    content.lazy.compactMap(\.navigationBarHidden).first
}

@MainActor
private func navigationDestinations(in content: [AnyView]) -> [NavigationDestinationRegistration] {
    content.flatMap(\.navigationDestinationRegistrations)
}

@MainActor
private func navigationPresentedDestinations(in content: [AnyView]) -> [NavigationPresentedDestination] {
    content.flatMap(\.navigationPresentedDestinations)
}

@MainActor
private func activeNavigationPresentation(
    in presentations: [NavigationPresentedDestination]
) -> (destination: [AnyView], dismiss: () -> Void)? {
    for presentation in presentations.reversed() {
        guard let destination = presentation.destination(), !destination.isEmpty else {
            continue
        }

        return (destination, presentation.dismiss)
    }

    return nil
}

@MainActor
private func resolveNavigationDestination(
    for value: AnyHashable,
    registrations: [NavigationDestinationRegistration]
) -> [AnyView]? {
    for registration in registrations.reversed() {
        if let destination = registration.resolve(value) {
            return destination
        }
    }

    return nil
}

@MainActor
private func resolvedNavigationStack(
    from values: [AnyHashable],
    registrations: [NavigationDestinationRegistration]
) -> [[AnyView]] {
    var stack: [[AnyView]] = []
    var availableRegistrations = registrations
    for value in values {
        guard let destination = resolveNavigationDestination(for: value, registrations: availableRegistrations) else {
            break
        }

        stack.append(destination)
        availableRegistrations += navigationDestinations(in: destination)
    }

    return stack
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
        let visibleColumns = visibleColumns()
        let style = context.navigationSplitViewStyle
        let columnComponents = visibleColumns.map { column in
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
                children: columnComponents.enumerated().map { index, component in
                    let node = component.makeNode(runtime: runtime)
                    Self.applyRetainedColumnStyle(
                        to: node,
                        index: index,
                        count: columnComponents.count,
                        style: style
                    )
                    return node
                }
            )
        }
    }

    private static func applyRetainedColumnStyle(
        to node: ViewNode,
        index: Int,
        count: Int,
        style: NavigationSplitViewStyle
    ) {
        switch style.kind {
        case .automatic:
            node.layoutPriority = 1
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .balanced:
            node.layoutPriority = 1
            node.backgroundColor = Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.24)
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .prominentDetail:
            let isDetail = index == count - 1
            node.layoutPriority = isDetail ? 2 : 0.75
            node.backgroundColor = isDetail
                ? Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.30)
                : Color(red: 0.06, green: 0.09, blue: 0.13, alpha: 0.28)
            node.borderColor = isDetail ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.12)
            node.borderWidth = isDetail ? 0 : 1
        }
    }

    private func visibleColumns() -> [[AnyView]] {
        guard let visibility = columnVisibility?.wrappedValue else {
            return columns
        }

        switch visibility {
        case .automatic, .all:
            return columns
        case .doubleColumn:
            guard columns.count > 2 else {
                return columns
            }
            return Array(columns.suffix(2))
        case .detailOnly:
            return columns.last.map { [$0] } ?? []
        }
    }
}

@MainActor
public struct NavigationLink: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let destination: [AnyView]
    private let value: AnyHashable?
    private let isActive: Binding<Bool>?
    private let activateSelection: (@MainActor () -> Void)?
    private let dismissSelection: (@MainActor () -> Void)?

    public init<Destination: View>(
        destination: Destination,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init(
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Destination: View>(
        destination: Destination,
        isActive: Binding<Bool>,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init(
        isActive: Binding<Bool>,
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Destination: View, Selection: Hashable>(
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = {
            selection.wrappedValue = tag
        }
        self.dismissSelection = {
            if selection.wrappedValue == tag {
                selection.wrappedValue = nil
            }
        }
    }

    public init<Selection: Hashable>(
        tag: Selection,
        selection: Binding<Selection?>,
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = nil
        self.activateSelection = {
            selection.wrappedValue = tag
        }
        self.dismissSelection = {
            if selection.wrappedValue == tag {
                selection.wrappedValue = nil
            }
        }
    }

    public init<Destination: View>(
        _ title: String,
        destination: Destination
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Destination: View>(
        _ title: S,
        destination: Destination
    ) {
        self.init(String(title), destination: destination)
    }

    public init<Destination: View>(
        _ titleKey: LocalizedStringKey,
        destination: Destination
    ) {
        self.init(titleKey.resolvedString, destination: destination)
    }

    public init<Destination: View>(
        _ title: String,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Destination: View>(
        _ title: S,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.init(String(title), destination: destination, isActive: isActive)
    }

    public init<Destination: View>(
        _ titleKey: LocalizedStringKey,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.init(titleKey.resolvedString, destination: destination, isActive: isActive)
    }

    public init<Destination: View, Selection: Hashable>(
        _ title: String,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(destination: destination, tag: tag, selection: selection) {
            Text(title)
        }
    }

    public init<S: StringProtocol, Destination: View, Selection: Hashable>(
        _ title: S,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(String(title), destination: destination, tag: tag, selection: selection)
    }

    public init<Destination: View, Selection: Hashable>(
        _ titleKey: LocalizedStringKey,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(titleKey.resolvedString, destination: destination, tag: tag, selection: selection)
    }

    public init<Value: Hashable>(
        value: Value,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = []
        self.value = AnyHashable(value)
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Value: Hashable>(
        _ title: String,
        value: Value
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = []
        self.value = AnyHashable(value)
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Value: Hashable>(
        _ title: S,
        value: Value
    ) {
        self.init(String(title), value: value)
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
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )

        if destination.isEmpty, value == nil {
            return labelComponent
        }

        let destinationViews = destination
        let navigationValue = value
        let activeBinding = isActive
        let activateSelection = activateSelection
        let dismissSelection = dismissSelection
        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                layoutMode: .stack(.vertical(
                    padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                    alignment: .stretch,
                    mainAlignment: .center
                )),
                isEnabled: context.isEnabled,
                action: {
                    if let navigationValue {
                        _ = context.pushNavigationValue(navigationValue)
                    } else if let activeBinding {
                        activeBinding.wrappedValue = true
                        _ = context.pushNavigationDestination(destinationViews) {
                            activeBinding.wrappedValue = false
                        }
                    } else if let activateSelection {
                        activateSelection()
                        _ = context.pushNavigationDestination(destinationViews, onDismiss: dismissSelection)
                    } else {
                        _ = context.pushNavigationDestination(destinationViews)
                    }
                },
                children: [labelNode]
            )
        }
    }
}

@MainActor
public struct TabView: View {
    public typealias Body = Never

    private final class TabState {
        var selectedIndex = 0
    }

    private let state = TabState()
    private let content: [AnyView]
    private let selectedTag: (@MainActor () -> AnyHashable?)?
    private let setSelectedTag: (@MainActor (AnyHashable) -> Void)?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.selectedTag = nil
        self.setSelectedTag = nil
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectedTag = {
            AnyHashable(selection.wrappedValue)
        }
        self.setSelectedTag = { tag in
            guard let value = tag.base as? SelectionValue else {
                return
            }
            selection.wrappedValue = value
        }
    }

    public var body: Never {
        fatalError("TabView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        guard !content.isEmpty else {
            return composeComponent(from: [], context: context)
        }

        let selectedIndex = selectedPageIndex()
        let page = composeComponent(
            from: [content[selectedIndex]],
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
        let tabBar = tabBarComponent(selectedIndex: selectedIndex, context: context)

        return Component { runtime in
            let tabBarNode = tabBar.makeNode(runtime: runtime)
            let pageNode = page.makeNode(runtime: runtime)
            var children = [tabBarNode, pageNode]
            if let pageIndexNode = Self.retainedPageIndexNode(
                selectedIndex: selectedIndex,
                count: content.count,
                tabViewStyle: context.tabViewStyle,
                indexViewStyle: context.indexViewStyle,
                tint: context.tint
            ) {
                children.append(pageIndexNode)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 10, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private func selectedPageIndex() -> Int {
        guard !content.isEmpty else {
            return 0
        }

        if let selectedTag = selectedTag?(),
           let selectedIndex = content.firstIndex(where: { $0.selectionTag == selectedTag }) {
            return selectedIndex
        }

        if selectedTag == nil {
            state.selectedIndex = min(max(0, state.selectedIndex), content.count - 1)
            return state.selectedIndex
        }

        return 0
    }

    private func tabBarComponent(selectedIndex: Int, context: ViewBuildContext) -> Component {
        Component { runtime in
            let chrome = Self.retainedTabChrome(for: context.tabViewStyle)
            let tabNodes = content.enumerated().map { index, view in
                let labelViews = view.tabItem ?? [AnyView(Text("TAB \(index + 1)"))]
                let labelNode = composeComponent(
                    from: labelViews,
                    context: context,
                    fallbackLayout: .stack(.horizontal(spacing: 4, alignment: .center))
                )
                .makeNode(runtime: runtime)
                let tabContentNode: ViewNode
                if let badgeViews = view.badge {
                    tabContentNode = Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 6, padding: .zero, alignment: .center),
                        isHitTestVisible: false,
                        children: [
                            labelNode,
                            context.makeRetainedBadgeNode(from: badgeViews, runtime: runtime),
                        ]
                    )
                } else {
                    tabContentNode = labelNode
                }
                let isSelected = index == selectedIndex
                let palette = isSelected
                    ? ButtonSurfaceStyle.default.palette
                    : ButtonSurfaceStyle.plain.palette

                return Controls.button(
                    runtime: runtime,
                    layoutPriority: 1,
                    cornerRadius: chrome.tabCornerRadius,
                    palette: palette,
                    chrome: SurfaceChrome(
                        borderColor: isSelected ? context.tint.opacity(chrome.selectedBorderAlpha) : chrome.unselectedBorderColor,
                        borderHoveredColor: context.tint.opacity(isSelected ? 0.62 : chrome.hoverBorderAlpha),
                        borderFocusedColor: context.tint.opacity(0.68),
                        borderPressedColor: context.tint.opacity(0.78),
                        borderWidth: isSelected ? chrome.selectedBorderWidth : chrome.unselectedBorderWidth,
                        focusRingColor: context.tint.opacity(0.24),
                        focusRingWidth: 2
                    ),
                    layoutMode: .stack(.vertical(
                        padding: chrome.tabPadding,
                        alignment: .center,
                        mainAlignment: .center
                    )),
                    isEnabled: context.isEnabled,
                    action: {
                        if let tag = view.selectionTag {
                            setSelectedTag?(tag)
                        }
                        state.selectedIndex = index
                        context.invalidate()
                    },
                    children: [tabContentNode]
                )
            }

            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: chrome.spacing,
                    padding: chrome.padding,
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: tabNodes
            )
        }
    }

    private struct RetainedTabChrome {
        var backgroundColor: Color
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
        var spacing: Double
        var padding: EdgeInsets
        var tabCornerRadius: Double
        var tabPadding: EdgeInsets
        var selectedBorderAlpha: Double
        var selectedBorderWidth: Double
        var unselectedBorderColor: Color
        var unselectedBorderWidth: Double
        var hoverBorderAlpha: Double
    }

    private struct RetainedPageIndexChrome {
        var backgroundColor: Color?
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
    }

    private static func retainedPageIndexNode(
        selectedIndex: Int,
        count: Int,
        tabViewStyle: TabViewStyle,
        indexViewStyle: IndexViewStyle,
        tint: Color
    ) -> ViewNode? {
        guard count > 1, shouldRenderPageIndex(for: tabViewStyle) else {
            return nil
        }

        let chrome = retainedPageIndexChrome(for: indexViewStyle)
        let dots = (0..<count).map { index in
            let isSelected = index == selectedIndex
            let node = Controls.panel(
                preferredSize: Size(width: isSelected ? 18 : 6, height: 6),
                backgroundColor: isSelected
                    ? tint.opacity(0.92)
                    : Color(red: 0.74, green: 0.80, blue: 0.90, alpha: 0.42),
                cornerRadius: 3,
                isHitTestVisible: false
            )
            node.nodeTag = isSelected ? "tab-page-index-selected" : "tab-page-index-unselected"
            return node
        }

        let node = Controls.stackPanel(
            backgroundColor: chrome.backgroundColor,
            borderColor: chrome.borderColor,
            borderWidth: chrome.borderWidth,
            cornerRadius: chrome.cornerRadius,
            stackLayout: .horizontal(
                spacing: 5,
                padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: dots
        )
        node.nodeTag = "tab-page-index"
        return node
    }

    private static func shouldRenderPageIndex(for style: TabViewStyle) -> Bool {
        switch style.kind {
        case .page(let indexDisplayMode):
            return indexDisplayMode != .never
        case .verticalPage:
            return true
        case .automatic, .sidebarAdaptable, .tabBarOnly, .grouped, .carousel:
            return false
        }
    }

    private static func retainedPageIndexChrome(for style: IndexViewStyle) -> RetainedPageIndexChrome {
        switch style.kind {
        case .page(let backgroundDisplayMode):
            switch backgroundDisplayMode.kind {
            case .automatic:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.34),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderWidth: 1,
                    cornerRadius: 9
                )
            case .always:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.72),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderWidth: 1,
                    cornerRadius: 10
                )
            case .interactive:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.52),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                    borderWidth: 1,
                    cornerRadius: 10
                )
            case .never:
                return RetainedPageIndexChrome(
                    backgroundColor: nil,
                    borderColor: .clear,
                    borderWidth: 0,
                    cornerRadius: 0
                )
            }
        }
    }

    private static func retainedTabChrome(for style: TabViewStyle) -> RetainedTabChrome {
        switch style.kind {
        case .automatic, .tabBarOnly:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.88),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 12,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                tabCornerRadius: 8,
                tabPadding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                selectedBorderAlpha: 0.42,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.24
            )
        case .grouped:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.74),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 16,
                spacing: 8,
                padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                tabCornerRadius: 10,
                tabPadding: EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14),
                selectedBorderAlpha: 0.50,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.06),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.28
            )
        case .sidebarAdaptable:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.70),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 8,
                spacing: 3,
                padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                tabCornerRadius: 6,
                tabPadding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                selectedBorderAlpha: 0.48,
                selectedBorderWidth: 2,
                unselectedBorderColor: .clear,
                unselectedBorderWidth: 0,
                hoverBorderAlpha: 0.22
            )
        case .page, .verticalPage:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 0.48),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.06),
                borderWidth: 1,
                cornerRadius: 20,
                spacing: 6,
                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                tabCornerRadius: 16,
                tabPadding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                selectedBorderAlpha: 0.58,
                selectedBorderWidth: 1,
                unselectedBorderColor: .clear,
                unselectedBorderWidth: 0,
                hoverBorderAlpha: 0.18
            )
        case .carousel:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.58),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 18,
                spacing: 10,
                padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                tabCornerRadius: 14,
                tabPadding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
                selectedBorderAlpha: 0.56,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.05),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.20
            )
        }
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

    public enum TruncationMode: Sendable, Equatable {
        case head
        case tail
        case middle
    }

    public enum Case: Sendable, Equatable {
        case uppercase
        case lowercase
    }

    public struct DateStyle: Sendable, Equatable, Hashable, Codable {
        fileprivate enum Kind: String, Sendable, Equatable, Hashable, Codable {
            case date
            case time
            case relative
            case offset
            case timer
        }

        fileprivate let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawKind = try container.decode(String.self)
            guard let kind = Kind(rawValue: rawKind) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown Text.DateStyle value: \(rawKind)"
                )
            }
            self.kind = kind
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(kind.rawValue)
        }

        public static let date = DateStyle(kind: .date)
        public static let time = DateStyle(kind: .time)
        public static let relative = DateStyle(kind: .relative)
        public static let offset = DateStyle(kind: .offset)
        public static let timer = DateStyle(kind: .timer)
    }

    public struct LineStyle: Sendable, Equatable {
        public enum Pattern: Sendable, Equatable, Hashable {
            case solid
            case dot
            case dash
            case dashDot
            case dashDotDot
        }

        public var pattern: Pattern
        public var color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }
    }

    private let content: String
    private var color: Color?
    private var font: Font??
    private var fontDesign: Font.Design?
    private var isItalic: Bool?
    private var monospacedDigits: Bool
    private var alignment: TextAlignment?
    private var lineLimit: Int??
    private var minimumLineLimit: Int??
    private var lineLimitReservesSpace: Bool?
    private var truncationMode: TruncationMode?
    private var letterSpacing: Double?
    private var lineSpacing: Double?
    private var minimumScaleFactor: CGFloat?
    private var allowsTightening: Bool?
    private var textCase: Case??
    private var baselineOffset: CGFloat?
    private var underline: Bool?
    private var underlinePattern: LineStyle.Pattern
    private var underlineColor: Color?
    private var strikethrough: Bool?
    private var strikethroughPattern: LineStyle.Pattern
    private var strikethroughColor: Color?

    public init(_ content: String) {
        self.content = content
        self.color = nil
        self.font = nil
        self.fontDesign = nil
        self.isItalic = nil
        self.monospacedDigits = false
        self.alignment = nil
        self.lineLimit = nil
        self.minimumLineLimit = nil
        self.lineLimitReservesSpace = nil
        self.truncationMode = nil
        self.letterSpacing = nil
        self.lineSpacing = nil
        self.minimumScaleFactor = nil
        self.allowsTightening = nil
        self.textCase = nil
        self.baselineOffset = nil
        self.underline = nil
        self.underlinePattern = .solid
        self.underlineColor = nil
        self.strikethrough = nil
        self.strikethroughPattern = .solid
        self.strikethroughColor = nil
    }

    private init(
        content: String,
        color: Color?,
        font: Font??,
        fontDesign: Font.Design?,
        isItalic: Bool?,
        monospacedDigits: Bool,
        alignment: TextAlignment?,
        lineLimit: Int??,
        minimumLineLimit: Int??,
        lineLimitReservesSpace: Bool?,
        truncationMode: TruncationMode?,
        letterSpacing: Double?,
        lineSpacing: Double?,
        minimumScaleFactor: CGFloat?,
        allowsTightening: Bool?,
        textCase: Case??,
        baselineOffset: CGFloat?,
        underline: Bool?,
        underlinePattern: LineStyle.Pattern,
        underlineColor: Color?,
        strikethrough: Bool?,
        strikethroughPattern: LineStyle.Pattern,
        strikethroughColor: Color?
    ) {
        self.content = content
        self.color = color
        self.font = font
        self.fontDesign = fontDesign
        self.isItalic = isItalic
        self.monospacedDigits = monospacedDigits
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.minimumLineLimit = minimumLineLimit
        self.lineLimitReservesSpace = lineLimitReservesSpace
        self.truncationMode = truncationMode
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.minimumScaleFactor = minimumScaleFactor
        self.allowsTightening = allowsTightening
        self.textCase = textCase
        self.baselineOffset = baselineOffset
        self.underline = underline
        self.underlinePattern = underline == true ? underlinePattern : .solid
        self.underlineColor = underline == true ? underlineColor : nil
        self.strikethrough = strikethrough
        self.strikethroughPattern = strikethrough == true ? strikethroughPattern : .solid
        self.strikethroughColor = strikethrough == true ? strikethroughColor : nil
    }

    public init(
        _ key: LocalizedStringKey,
        tableName: String? = nil,
        bundle: Bundle? = nil,
        comment: StaticString? = nil
    ) {
        _ = tableName
        _ = bundle
        _ = comment
        self.init(key.resolvedString)
    }

    public init(_ resource: LocalizedStringResource) {
        self.init(resource.resolvedString)
    }

    public init(_ date: Date, style: DateStyle) {
        self.init(Self.formattedDateText(date, style: style))
    }

    public init(_ interval: DateInterval) {
        let startText = Self.formattedDateTimeText(interval.start)
        let endText = Self.formattedDateTimeText(interval.end)
        self.init("\(startText) - \(endText)")
    }

    public init(
        timerInterval: ClosedRange<Date>,
        pauseTime: Date? = nil,
        countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        self.init(
            Self.formattedTimerIntervalText(
                timerInterval,
                pauseTime: pauseTime,
                countsDown: countsDown,
                showsHours: showsHours
            )
        )
    }

    public init<Subject>(_ subject: Subject, formatter: Formatter) {
        self.init(formatter.string(for: subject) ?? String(describing: subject))
    }

    public init(_ attributedContent: AttributedString) {
        self.init(Self.flattenedAttributedText(attributedContent))
    }

    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(format.format(input))
    }

    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == AttributedString {
        self.init(Self.flattenedAttributedText(format.format(input)))
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

    private static func formattedDateText(_ date: Date, style: DateStyle) -> String {
        switch style.kind {
        case .date:
            return formattedDateOnlyText(date)
        case .time:
            return formattedTimeOnlyText(date)
        case .relative, .offset, .timer:
            return formattedDateTimeText(date)
        }
    }

    private static func formattedDateOnlyText(_ date: Date) -> String {
        let components = retainedUTCDateComponents(for: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func formattedTimeOnlyText(_ date: Date) -> String {
        let components = retainedUTCDateComponents(for: date)
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private static func formattedDateTimeText(_ date: Date) -> String {
        "\(formattedDateOnlyText(date)) \(formattedTimeOnlyText(date))"
    }

    private static func retainedUTCDateComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private static func flattenedAttributedText(_ attributedContent: AttributedString) -> String {
        String(attributedContent.characters)
    }

    private static func formattedTimerIntervalText(
        _ interval: ClosedRange<Date>,
        pauseTime: Date?,
        countsDown: Bool,
        showsHours: Bool
    ) -> String {
        let duration = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard duration > 0 else {
            return formatTimerDuration(0, showsHours: showsHours)
        }

        let referenceDate = pauseTime ?? Date()
        let elapsed = referenceDate.timeIntervalSince(interval.lowerBound)
        let unclampedSeconds = countsDown ? duration - elapsed : elapsed
        let clampedSeconds = min(max(unclampedSeconds, 0), duration)
        return formatTimerDuration(clampedSeconds, showsHours: showsHours)
    }

    private static func formatTimerDuration(_ seconds: TimeInterval, showsHours: Bool) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if showsHours, hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        let totalMinutes = totalSeconds / 60
        return String(format: "%d:%02d", totalMinutes, seconds)
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(
            content: lhs.content + rhs.content,
            color: lhs.color ?? rhs.color,
            font: lhs.font != nil ? lhs.font : rhs.font,
            fontDesign: lhs.fontDesign ?? rhs.fontDesign,
            isItalic: lhs.isItalic != nil ? lhs.isItalic : rhs.isItalic,
            monospacedDigits: lhs.monospacedDigits || rhs.monospacedDigits,
            alignment: lhs.alignment ?? rhs.alignment,
            lineLimit: lhs.lineLimit != nil ? lhs.lineLimit : rhs.lineLimit,
            minimumLineLimit: lhs.minimumLineLimit != nil ? lhs.minimumLineLimit : rhs.minimumLineLimit,
            lineLimitReservesSpace: lhs.lineLimitReservesSpace ?? rhs.lineLimitReservesSpace,
            truncationMode: lhs.truncationMode ?? rhs.truncationMode,
            letterSpacing: lhs.letterSpacing ?? rhs.letterSpacing,
            lineSpacing: lhs.lineSpacing ?? rhs.lineSpacing,
            minimumScaleFactor: lhs.minimumScaleFactor ?? rhs.minimumScaleFactor,
            allowsTightening: lhs.allowsTightening ?? rhs.allowsTightening,
            textCase: lhs.textCase != nil ? lhs.textCase : rhs.textCase,
            baselineOffset: lhs.baselineOffset ?? rhs.baselineOffset,
            underline: lhs.underline != nil ? lhs.underline : rhs.underline,
            underlinePattern: lhs.underline != nil ? lhs.underlinePattern : rhs.underlinePattern,
            underlineColor: lhs.underline != nil ? lhs.underlineColor : rhs.underlineColor,
            strikethrough: lhs.strikethrough != nil ? lhs.strikethrough : rhs.strikethrough,
            strikethroughPattern: lhs.strikethrough != nil ? lhs.strikethroughPattern : rhs.strikethroughPattern,
            strikethroughColor: lhs.strikethrough != nil ? lhs.strikethroughColor : rhs.strikethroughColor
        )
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let resolvedColor = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let inheritedFont = context.fontWeight.map { context.font.weight($0) } ?? context.font
        var resolvedFont: Font
        if let font {
            resolvedFont = font ?? .system(size: 2)
        } else {
            resolvedFont = inheritedFont
        }
        if let fontDesign {
            resolvedFont = resolvedFont.withDesign(fontDesign)
        }
        resolvedFont = resolvedFont.scaled(for: context.dynamicTypeSize)
        let resolvedAlignment = alignment ?? context.textAlignment
        let resolvedLineLimit: Int?
        if let lineLimit {
            resolvedLineLimit = lineLimit
        } else {
            resolvedLineLimit = context.lineLimit
        }
        let resolvedMinimumLineLimit: Int?
        if let minimumLineLimit {
            resolvedMinimumLineLimit = minimumLineLimit
        } else {
            resolvedMinimumLineLimit = context.minimumLineLimit
        }

        let resolvedContent = content.resolvedTextCase(textCase ?? context.textCase)
        let redactionReasons = context.environmentValues.redactionReasons.retainedReasons
        let isPrivacySensitive = context.environmentValues.isPrivacySensitive
        let resolvedUnderline = underline ?? context.underlineStyle?.isActive ?? false
        let resolvedUnderlinePattern = (underline != nil ? underlinePattern : context.underlineStyle?.pattern ?? .solid)
            .retainedTextDecorationPattern
        let resolvedUnderlineColor = underline != nil ? underlineColor : context.underlineStyle?.color
        let resolvedStrikethrough = strikethrough ?? context.strikethroughStyle?.isActive ?? false
        let resolvedStrikethroughPattern = (strikethrough != nil ? strikethroughPattern : context.strikethroughStyle?.pattern ?? .solid)
            .retainedTextDecorationPattern
        let resolvedStrikethroughColor = strikethrough != nil ? strikethroughColor : context.strikethroughStyle?.color

        return Component { _ in
            let node = Controls.label(
                resolvedContent,
                color: resolvedColor,
                scale: resolvedFont.resolvedScale,
                weight: resolvedFont.weight.textWeight,
                isItalic: isItalic ?? context.isFontItalic,
                monospacedDigits: monospacedDigits || context.usesMonospacedDigits,
                fontFamily: resolvedFont.resolvedFamily,
                nativeFontSize: resolvedFont.resolvedNativeTextSize,
                alignment: resolvedAlignment.textAlignment(layoutDirection: context.layoutDirection),
                letterSpacing: letterSpacing ?? 1,
                lineSpacing: lineSpacing ?? context.lineSpacing ?? resolvedFont.resolvedLineSpacing,
                lineBreakMode: resolvedLineBreakMode(
                    lineLimit: resolvedLineLimit,
                    truncationMode: truncationMode ?? context.truncationMode
                ),
                maximumNumberOfLines: resolvedLineLimit,
                minimumNumberOfLines: resolvedMinimumLineLimit,
                minimumScaleFactor: minimumScaleFactor ?? context.minimumScaleFactor,
                reservesLineLimitSpace: (lineLimitReservesSpace ?? context.lineLimitReservesSpace) && resolvedLineLimit != nil,
                underline: resolvedUnderline,
                underlinePattern: resolvedUnderlinePattern,
                underlineColor: resolvedUnderlineColor,
                strikethrough: resolvedStrikethrough,
                strikethroughPattern: resolvedStrikethroughPattern,
                strikethroughColor: resolvedStrikethroughColor,
                enableKerning: allowsTightening ?? context.allowsTightening
            )
            node.redactionReasons = redactionReasons
            node.isPrivacySensitive = isPrivacySensitive
            if let baselineOffset, baselineOffset != 0 {
                node.transform = node.transform.concatenating(.translation(x: 0, y: -Double(baselineOffset)))
            }
            return node
        }
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Text {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color) -> Text {
        foregroundColor(color)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Text {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ style: ForegroundStyle) -> Text {
        foregroundColor(resolvedFill(from: style).color)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle, _ tertiary: ForegroundStyle) -> Text {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ gradient: LinearGradient) -> Text {
        foregroundStyle(.linearGradient(gradient))
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient, _ tertiary: LinearGradient) -> Text {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func font(_ font: Font) -> Text {
        var copy = self
        copy.font = .some(font)
        return copy
    }

    public func font(_ font: Font?) -> Text {
        var copy = self
        copy.font = .some(font)
        return copy
    }

    public func monospaced() -> Text {
        monospaced(true)
    }

    public func monospaced(_ isActive: Bool) -> Text {
        var copy = self
        copy.fontDesign = isActive ? .monospaced : .default
        return copy
    }

    public func fontDesign(_ design: Font.Design?) -> Text {
        var copy = self
        copy.fontDesign = design
        return copy
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var copy = self
        guard let weight else {
            if let font = copy.font, let resolvedFont = font {
                copy.font = .some(resolvedFont.weight(.regular))
            }
            return copy
        }

        let baseFont: Font
        if let font = copy.font {
            baseFont = font ?? .system(size: 2)
        } else {
            baseFont = .system(size: 2)
        }
        copy.font = .some(baseFont.weight(weight))
        return copy
    }

    public func bold() -> Text {
        bold(true)
    }

    public func bold(_ isActive: Bool) -> Text {
        fontWeight(isActive ? .bold : .regular)
    }

    public func italic() -> Text {
        italic(true)
    }

    public func italic(_ isActive: Bool) -> Text {
        var copy = self
        copy.isItalic = isActive
        return copy
    }

    public func monospacedDigit() -> Text {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ lineLimit: Int?) -> Text {
        var copy = self
        copy.lineLimit = .some(lineLimit)
        copy.minimumLineLimit = .some(nil)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ lineLimit: Int, reservesSpace: Bool) -> Text {
        var copy = self
        copy.lineLimit = .some(lineLimit)
        copy.minimumLineLimit = .some(reservesSpace ? lineLimit : nil)
        copy.lineLimitReservesSpace = reservesSpace
        return copy
    }

    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(limit.upperBound)
        copy.minimumLineLimit = .some(nil)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(nil)
        copy.minimumLineLimit = .some(limit.lowerBound)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ limits: ClosedRange<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(limits.upperBound)
        copy.minimumLineLimit = .some(limits.lowerBound)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func truncationMode(_ mode: TruncationMode) -> Text {
        var copy = self
        copy.truncationMode = mode
        return copy
    }

    public func lineSpacing(_ lineSpacing: Double) -> Text {
        var copy = self
        copy.lineSpacing = lineSpacing
        return copy
    }

    public func minimumScaleFactor(_ factor: CGFloat) -> Text {
        var copy = self
        copy.minimumScaleFactor = EnvironmentValues.clampedMinimumScaleFactor(factor)
        return copy
    }

    public func kerning(_ kerning: Double) -> Text {
        var copy = self
        copy.letterSpacing = kerning
        return copy
    }

    public func tracking(_ tracking: Double) -> Text {
        kerning(tracking)
    }

    public func allowsTightening(_ flag: Bool) -> Text {
        var copy = self
        copy.allowsTightening = flag
        return copy
    }

    public func textCase(_ textCase: Case?) -> Text {
        var copy = self
        copy.textCase = .some(textCase)
        return copy
    }

    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        var copy = self
        copy.baselineOffset = baselineOffset
        return copy
    }

    public func underline(
        _ active: Bool = true,
        pattern: LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> Text {
        var copy = self
        copy.underline = active
        copy.underlinePattern = active ? pattern : .solid
        copy.underlineColor = active ? color : nil
        return copy
    }

    public func underline(_ style: LineStyle) -> Text {
        underline(true, pattern: style.pattern, color: style.color)
    }

    public func strikethrough(
        _ active: Bool = true,
        pattern: LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> Text {
        var copy = self
        copy.strikethrough = active
        copy.strikethroughPattern = active ? pattern : .solid
        copy.strikethroughColor = active ? color : nil
        return copy
    }

    public func strikethrough(_ style: LineStyle) -> Text {
        strikethrough(true, pattern: style.pattern, color: style.color)
    }

    private func resolvedLineBreakMode(lineLimit: Int?, truncationMode: TruncationMode?) -> TextLineBreakMode {
        guard let lineLimit else {
            return .wrap
        }
        guard lineLimit == 1 || truncationMode != nil else {
            return .wrap
        }

        switch truncationMode {
        case .head:
            return .truncateHead
        case .tail, nil:
            return .truncateTail
        case .middle:
            return .truncateMiddle
        }
    }
}

private extension String {
    func resolvedTextCase(_ textCase: Text.Case?) -> String {
        switch textCase {
        case .uppercase:
            return uppercased()
        case .lowercase:
            return lowercased()
        case nil:
            return self
        }
    }
}

private extension Text.LineStyle.Pattern {
    var retainedTextDecorationPattern: TextDecorationPattern {
        switch self {
        case .solid:
            return .solid
        case .dot:
            return .dot
        case .dash:
            return .dash
        case .dashDot:
            return .dashDot
        case .dashDotDot:
            return .dashDotDot
        }
    }
}

@MainActor
public struct Image: View {
    public typealias Body = Never

    public enum Scale: Sendable, Equatable {
        case small
        case medium
        case large
    }

    public enum ResizingMode: Sendable, Equatable {
        case tile
        case stretch
    }

    public enum TemplateRenderingMode: Sendable, Equatable {
        case template
        case original
    }

    public enum Interpolation: Sendable, Equatable {
        case none
        case low
        case medium
        case high
    }

    private enum Storage {
        case systemName(String)
        case bitmap(BitmapSurface?)
    }

    private let storage: Storage
    private var color: Color?
    private var font: Font
    private var alignment: TextAlignment
    private var isResizable: Bool
    private var resizingMode: ResizingMode
    private var capInsets: EdgeInsets
    private var aspectRatioValue: Double?
    private var contentMode: ContentMode?
    private var renderingMode: TemplateRenderingMode?
    private var interpolation: Interpolation
    private var antialiased: Bool?
    private var accessibilityLabel: String?
    private var isAccessibilityHidden: Bool
    private var symbolVariableValue: Double?

    public init(systemName: String) {
        self.init(storage: .systemName(systemName))
    }

    public init(systemName: String, label: Text) {
        self.init(systemName: systemName)
        self.accessibilityLabel = label.plainContent
    }

    public init(systemName: String, variableValue: Double?) {
        self.init(systemName: systemName)
        self.symbolVariableValue = variableValue
    }

    public init(systemName: String, variableValue: Double?, label: Text) {
        self.init(systemName: systemName, variableValue: variableValue)
        self.accessibilityLabel = label.plainContent
    }

    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(storage: .bitmap(Self.loadResource(named: name, bundle: bundle)))
    }

    public init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.init(name, bundle: bundle)
        self.symbolVariableValue = variableValue
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.init(name, bundle: bundle)
        self.accessibilityLabel = label.plainContent
    }

    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil, label: Text) {
        self.init(name, variableValue: variableValue, bundle: bundle)
        self.accessibilityLabel = label.plainContent
    }

    public init(decorative name: String, bundle: Bundle? = nil) {
        self.init(name, bundle: bundle)
        self.isAccessibilityHidden = true
    }

    public init(decorative name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.init(name, variableValue: variableValue, bundle: bundle)
        self.isAccessibilityHidden = true
    }

    private init(storage: Storage) {
        self.storage = storage
        self.color = nil
        self.font = .system(size: 1.9)
        self.alignment = .center
        self.isResizable = false
        self.resizingMode = .stretch
        self.capInsets = .zero
        self.aspectRatioValue = nil
        self.contentMode = nil
        self.renderingMode = nil
        self.interpolation = .medium
        self.antialiased = nil
        self.accessibilityLabel = nil
        self.isAccessibilityHidden = false
        self.symbolVariableValue = nil
    }

    public var body: Never {
        fatalError("Image has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        switch storage {
        case .systemName(let systemName):
            let symbolVariants = context.symbolVariants
            let symbol = resolvedSymbolIcon(for: systemName, variants: symbolVariants)
            let resolvedColor = (color ?? context.foregroundColor)
                .resolvedForVisualEnvironment(
                    contrast: context.colorSchemeContrast,
                    backgroundProminence: context.backgroundProminence
                )
            let renderedColor = retainedSymbolColor(
                base: resolvedColor,
                mode: context.symbolRenderingMode,
                tint: context.tint
            )
            let imageScale = context.imageScale.resolvedMultiplier
            let resolvedScale = font.resolvedScale * imageScale
            let baseSize = Size(width: font.resolvedNativeTextSize * imageScale, height: font.resolvedNativeTextSize * imageScale)
            let preferredSize = resolvedPreferredSize(baseSize: baseSize, requiresExplicitOptIn: true)
            return Component { _ in
                let node = Controls.icon(
                    symbol,
                    preferredSize: preferredSize,
                    color: renderedColor,
                    scale: resolvedScale,
                    alignment: alignment.textAlignment(layoutDirection: context.layoutDirection)
                )
                if symbolVariants.contains(.fill) {
                    node.textStyle.weight = .bold
                }
                applyImageMetadata(to: node, context: context)
                return retainedSymbolVariantNode(
                    iconNode: node,
                    iconSize: preferredSize ?? baseSize,
                    variants: symbolVariants,
                    tint: renderedColor,
                    context: context
                )
            }
        case .bitmap(let bitmap):
            let preferredSize = resolvedPreferredSize(baseSize: bitmap?.logicalSize, requiresExplicitOptIn: false)
            return Component { _ in
                guard let bitmap else {
                    let node = Controls.panel(preferredSize: preferredSize, isHitTestVisible: false)
                    applyImageMetadata(to: node, context: context)
                    return node
                }

                let renderedBitmap = resolvedBitmapSurface(bitmap, context: context)
                let node = Controls.image(renderedBitmap, preferredSize: preferredSize)
                applyImageMetadata(to: node, context: context)
                return node
            }
        }
    }

    public func foregroundColor(_ color: Color) -> Image {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Image {
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
        var copy = self
        copy.isResizable = true
        copy.resizingMode = resizingMode
        copy.capInsets = capInsets
        return copy
    }

    public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> Image {
        var copy = self
        copy.aspectRatioValue = aspectRatio
        copy.contentMode = contentMode
        return copy
    }

    public func scaledToFit() -> Image {
        aspectRatio(contentMode: .fit)
    }

    public func scaledToFill() -> Image {
        aspectRatio(contentMode: .fill)
    }

    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var copy = self
        copy.renderingMode = renderingMode
        return copy
    }

    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolation = interpolation
        return copy
    }

    public func antialiased(_ isAntialiased: Bool) -> Image {
        var copy = self
        copy.antialiased = isAntialiased
        return copy
    }

    private func resolvedPreferredSize(baseSize: Size?, requiresExplicitOptIn: Bool) -> Size? {
        guard let baseSize else {
            return nil
        }

        guard isResizable || contentMode != nil || !requiresExplicitOptIn else {
            return nil
        }

        let nativeRatio = baseSize.width > 0 && baseSize.height > 0 ? baseSize.width / baseSize.height : 1
        let requestedRatio = aspectRatioValue ?? nativeRatio
        let ratio = requestedRatio.isFinite && requestedRatio > 0 ? requestedRatio : 1
        guard let contentMode else {
            return baseSize
        }

        let baseRatio = nativeRatio.isFinite && nativeRatio > 0 ? nativeRatio : 1
        switch contentMode {
        case .fit:
            return ratio >= baseRatio
                ? Size(width: baseSize.width, height: baseSize.width / ratio)
                : Size(width: baseSize.height * ratio, height: baseSize.height)
        case .fill:
            return ratio >= baseRatio
                ? Size(width: baseSize.height * ratio, height: baseSize.height)
                : Size(width: baseSize.width, height: baseSize.width / ratio)
        }
    }

    private static func loadResource(named name: String, bundle: Bundle?) -> BitmapSurface? {
        guard let path = resolveResourcePath(named: name, bundle: bundle) else {
            return nil
        }

        return ImageLoader.load(contentsOfFile: path)
    }

    private static func resolveResourcePath(named name: String, bundle: Bundle?) -> String? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: name) {
            return name
        }

        let resourceBundle = bundle ?? .main
        let fileURL = URL(fileURLWithPath: name)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let extensionName = fileURL.pathExtension
        if !extensionName.isEmpty, let url = resourceBundle.url(forResource: baseName, withExtension: extensionName) {
            return url.path
        }

        if let url = resourceBundle.url(forResource: name, withExtension: nil) {
            return url.path
        }

        for extensionName in ["png", "jpg", "jpeg", "bmp"] {
            if let url = resourceBundle.url(forResource: name, withExtension: extensionName) {
                return url.path
            }
        }

        return nil
    }

    private func applyAccessibility(to node: ViewNode) {
        node.accessibilityLabel = accessibilityLabel
        node.isAccessibilityHidden = isAccessibilityHidden
    }

    private func resolvedBitmapSurface(_ bitmap: BitmapSurface, context: ViewBuildContext) -> BitmapSurface {
        guard renderingMode == .template else {
            return bitmap
        }

        let tint = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let tintChannels = tint.rgba
        let tintRed = templateByte(tintChannels.0)
        let tintGreen = templateByte(tintChannels.1)
        let tintBlue = templateByte(tintChannels.2)
        let tintAlpha = max(0, min(1, tintChannels.3))
        let width = max(0, Int(bitmap.width))
        let height = max(0, Int(bitmap.height))
        let bytesPerRow = max(width * 4, Int(bitmap.bytesPerRow))
        var pixels = bitmap.pixels

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                guard offset + 3 < pixels.count else {
                    continue
                }

                let sourceAlpha = Float(pixels[offset + 3]) / 255
                pixels[offset] = tintBlue
                pixels[offset + 1] = tintGreen
                pixels[offset + 2] = tintRed
                pixels[offset + 3] = templateByte(sourceAlpha * tintAlpha)
            }
        }

        return BitmapSurface(width: bitmap.width, height: bitmap.height, bytesPerRow: bitmap.bytesPerRow, pixels: pixels)
    }

    private func templateByte(_ value: Float) -> UInt8 {
        UInt8((max(0, min(1, value)) * 255).rounded())
    }

    private func retainedSymbolColor(
        base: Color,
        mode: SymbolRenderingMode?,
        tint: Color
    ) -> Color {
        guard let mode else {
            return base
        }

        switch mode.kind {
        case .monochrome:
            return base
        case .hierarchical:
            return base.opacity(0.72)
        case .palette:
            return tint
        case .multicolor:
            return Color(red: 0.30, green: 0.74, blue: 0.92, alpha: 1.0)
        }
    }

    private func retainedSymbolVariantNode(
        iconNode: ViewNode,
        iconSize: Size,
        variants: SymbolVariants,
        tint: Color,
        context: ViewBuildContext
    ) -> ViewNode {
        guard variants.contains(.circle)
            || variants.contains(.square)
            || variants.contains(.rectangle)
            || variants.contains(.slash) else {
            return iconNode
        }

        let hasShape = variants.contains(.circle) || variants.contains(.square) || variants.contains(.rectangle)
        let isRectangle = variants.contains(.rectangle)
        let widthMultiplier = isRectangle ? 1.65 : 1.35
        let boxSize = Size(
            width: max(iconSize.width, iconSize.width * widthMultiplier),
            height: max(iconSize.height, iconSize.height * 1.35)
        )
        let shapeCornerRadius: Double
        if variants.contains(.circle) {
            shapeCornerRadius = min(boxSize.width, boxSize.height) * 0.5
        } else if variants.contains(.square) {
            shapeCornerRadius = max(2, min(boxSize.width, boxSize.height) * 0.16)
        } else {
            shapeCornerRadius = max(2, min(boxSize.width, boxSize.height) * 0.12)
        }

        iconNode.frame = Rect(
            x: (boxSize.width - iconSize.width) * 0.5,
            y: (boxSize.height - iconSize.height) * 0.5,
            width: iconSize.width,
            height: iconSize.height
        )
        iconNode.preferredSize = iconSize

        var children = [iconNode]
        if variants.contains(.slash) {
            let slashThickness = max(2, min(boxSize.width, boxSize.height) * 0.10)
            let slashNode = Controls.panel(
                frame: Rect(
                    x: boxSize.width * 0.18,
                    y: (boxSize.height - slashThickness) * 0.5,
                    width: boxSize.width * 0.64,
                    height: slashThickness
                ),
                backgroundColor: tint,
                cornerRadius: slashThickness * 0.5,
                isHitTestVisible: false
            )
            slashNode.transform = Transform2D(rotation: -0.78)
            slashNode.nodeTag = "symbol-variant-slash"
            children.append(slashNode)
        }

        let variantNode = Controls.panel(
            preferredSize: boxSize,
            backgroundColor: hasShape && variants.contains(.fill) ? tint.opacity(0.18) : nil,
            borderColor: hasShape ? tint.opacity(variants.contains(.fill) ? 0.34 : 0.68) : .clear,
            borderWidth: hasShape ? 1 : 0,
            cornerRadius: hasShape ? shapeCornerRadius : 0,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: children
        )
        variantNode.nodeTag = "symbol-variant"
        applyImageMetadata(to: variantNode, context: context)
        return variantNode
    }

    private func applyImageMetadata(to node: ViewNode, context: ViewBuildContext) {
        applyAccessibility(to: node)
        node.symbolVariableValue = symbolVariableValue
        node.symbolRenderingMode = context.symbolRenderingMode?.retainedSymbolRenderingMode
        node.symbolVariants = context.symbolVariants.retainedSymbolVariants
        node.imageResizingMode = isResizable ? resizingMode.retainedImageResizingMode : nil
        node.imageCapInsets = isResizable ? capInsets : nil
        node.imageRenderingMode = renderingMode?.retainedImageRenderingMode
        node.imageInterpolation = interpolation.retainedImageInterpolation
        node.imageAntialiased = antialiased
    }
}

extension Image.ResizingMode {
    var retainedImageResizingMode: RetainedImageResizingMode {
        switch self {
        case .stretch:
            return .stretch
        case .tile:
            return .tile
        }
    }
}

extension Image.TemplateRenderingMode {
    var retainedImageRenderingMode: RetainedImageRenderingMode {
        switch self {
        case .original:
            return .original
        case .template:
            return .template
        }
    }
}

extension Image.Interpolation {
    var retainedImageInterpolation: RetainedImageInterpolation {
        switch self {
        case .none:
            return .none
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}

private extension BitmapSurface {
    var logicalSize: Size {
        Size(width: Double(width), height: Double(height))
    }
}

extension Text {
    var plainContent: String {
        content
    }
}

private extension Image.Scale {
    var resolvedMultiplier: Double {
        switch self {
        case .small:
            return 0.82
        case .medium:
            return 1.0
        case .large:
            return 1.25
        }
    }
}

@MainActor
public struct LabeledContent: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init<Title: StringProtocol, Value: StringProtocol>(_ title: Title, value: Value) {
        self.init(String(title)) {
            Text(String(value))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }

    public init<Value: StringProtocol>(_ titleKey: LocalizedStringKey, value: Value) {
        self.init(titleKey.resolvedString, value: String(value))
    }

    public init<F: FormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: F.FormatInput,
        format: F
    ) where F.FormatOutput == String {
        self.init(titleKey.resolvedString, value: format.format(value))
    }

    public init<S: StringProtocol, F: FormatStyle>(
        _ title: S,
        value: F.FormatInput,
        format: F
    ) where F.FormatOutput == String {
        self.init(String(title), value: format.format(value))
    }

    public var body: Never {
        fatalError("LabeledContent has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let contentComponent = composeComponent(
            from: content,
            context: context
                .withTextAlignment(.trailing)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let contentNode = contentComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, contentNode]
            )
        }
    }
}

@MainActor
public struct ToolbarItem: View {
    public typealias Body = Never

    public let id: String?
    public let placement: ToolbarItemPlacement
    public let showsByDefault: Bool
    private let content: [AnyView]

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = nil
        self.placement = placement
        self.showsByDefault = true
        self.content = content()
    }

    public init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        showsByDefault: Bool = true,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = id
        self.placement = placement
        self.showsByDefault = showsByDefault
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItem has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let item = composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )
        guard let id else {
            return item
        }

        return Component { runtime in
            let node = item.makeNode(runtime: runtime)
            node.nodeTag = id
            return node
        }
    }
}

@MainActor
public struct ToolbarItemGroup: View {
    public typealias Body = Never

    public let id: String?
    public let placement: ToolbarItemPlacement
    public let showsByDefault: Bool
    private let content: [AnyView]

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = nil
        self.placement = placement
        self.showsByDefault = true
        self.content = content()
    }

    public init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        showsByDefault: Bool = true,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = id
        self.placement = placement
        self.showsByDefault = showsByDefault
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItemGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let group = composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )
        guard let id else {
            return group
        }

        return Component { runtime in
            let node = group.makeNode(runtime: runtime)
            node.nodeTag = id
            return node
        }
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

    public init(_ title: String, image name: String) {
        self.title = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(name))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(String(title), image: name)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(titleKey.resolvedString, image: name)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource) {
        self.title = [
            AnyView(
                Text(String(title))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(resource))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource) {
        self.init(titleKey.resolvedString, image: resource)
    }

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

    public init<S: StringProtocol>(_ title: S, systemImage: String) {
        self.init(String(title), systemImage: systemImage)
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
        let resolvedColor = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let labelContext = context
            .withForegroundColor(resolvedColor)
            .withFont(font)
            .withTextAlignment(.leading)
            .withLineLimit(1)
        switch context.labelStyle.kind {
        case .automatic, .titleAndIcon:
            return HStack(spacing: spacing) {
                icon
                title
            }
            .makeComponent(context: labelContext)
        case .iconOnly:
            return composeComponent(from: icon, context: labelContext)
        case .titleOnly:
            return composeComponent(from: title, context: labelContext)
        }
    }

    public func foregroundColor(_ color: Color) -> Label {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Label {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color) -> Label {
        foregroundColor(color)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Label {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ style: ForegroundStyle) -> Label {
        foregroundColor(resolvedFill(from: style).color)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle, _ tertiary: ForegroundStyle) -> Label {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ gradient: LinearGradient) -> Label {
        foregroundStyle(.linearGradient(gradient))
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient, _ tertiary: LinearGradient) -> Label {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func font(_ font: Font) -> Label {
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

    public init(_ title: String, image name: String, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, image: name)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init<S: StringProtocol>(_ title: S, image name: String, description: Text? = nil) {
        self.init(String(title), image: name, description: description)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, description: Text? = nil) {
        self.init(titleKey.resolvedString, image: name, description: description)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, image: resource)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, description: Text? = nil) {
        self.init(titleKey.resolvedString, image: resource, description: description)
    }

    public init(_ title: String, systemImage: String, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, systemImage: systemImage)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, description: Text? = nil) {
        self.init(String(title), systemImage: systemImage, description: description)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(titleKey.resolvedString, systemImage: systemImage, description: description)
    }

    public static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
    }

    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No results for \(text)")
        )
    }

    public var body: Never {
        fatalError("ContentUnavailableView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context
                .withTextAlignment(.center)
                .withLineLimit(2),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false
        )
        let descriptionComponent = composeComponent(
            from: description,
            context: context
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.center),
            fallbackLayout: .stack(.vertical(spacing: 4, alignment: .center)),
            isHitTestVisible: false
        )
        let actionsComponent = composeComponent(
            from: actions,
            context: context.withButtonStyle(.bordered),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            var children = [labelComponent.makeNode(runtime: runtime)]
            if !description.isEmpty {
                children.append(descriptionComponent.makeNode(runtime: runtime))
            }
            if !actions.isEmpty {
                children.append(actionsComponent.makeNode(runtime: runtime))
            }

            return Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: 10,
                    padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                    alignment: .center,
                    mainAlignment: .center
                ),
                isHitTestVisible: false,
                children: children
            )
        }
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
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ),
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
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ),
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
public struct Grid: View {
    public typealias Body = Never

    private let alignment: Alignment
    private let horizontalSpacing: Double
    private let verticalSpacing: Double
    private let content: [AnyView]

    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Double? = nil,
        verticalSpacing: Double? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing ?? 0
        self.verticalSpacing = verticalSpacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("Grid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let verticalSpacing = verticalSpacing
        let horizontalSpacing = horizontalSpacing
        let childContext = context
            .withStackAxis(.vertical)
            .withEnvironmentValue(\.gridHorizontalSpacing, horizontalSpacing)
        let content = content

        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: verticalSpacing,
                    alignment: alignment.horizontal.stackAlignment(layoutDirection: context.layoutDirection)
                ),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}

@MainActor
public struct GridRow: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let content: [AnyView]

    public init(alignment: VerticalAlignment = .center, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("GridRow has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withStackAxis(.horizontal)
        let horizontalSpacing = context.gridHorizontalSpacing ?? 0
        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .horizontal(spacing: horizontalSpacing, alignment: alignment.stackAlignment),
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
                    let origin = alignment.frameOrigin(
                        for: childSize,
                        in: bounds.size,
                        layoutDirection: context.layoutDirection
                    )
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
    private let showsIndicators: Bool?
    private let content: [AnyView]

    @_disfavoredOverload
    public init(_ axis: Axis = .vertical, style: ScrollViewStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.axis = axis
        self.style = style
        self.showsIndicators = nil
        self.content = content()
    }

    public init(_ axes: Axis.Set, showsIndicators: Bool = true, @ViewBuilder content: () -> [AnyView]) {
        self.axis = axes.preferredRetainedAxis
        self.style = .default
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: Never {
        fatalError("ScrollView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let scrollIndicatorInsets = context.contentInsets(
                for: .scrollIndicators,
                defaultInsets: defaultRetainedScrollIndicatorInsets
            )
            let initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
            let scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
            let alignmentAnchor = context.defaultScrollAnchor(for: .alignment)
            let node = Controls.scrollPanel(
                axis: axis.scrollAxis,
                backgroundColor: context.scrollContentBackgroundVisibility.hidesRetainedScrollContentBackground ? nil : style.backgroundColor,
                borderColor: style.borderColor,
                borderWidth: style.borderWidth,
                shadowColor: style.shadowColor,
                shadowOffset: style.shadowOffset,
                shadowSpread: style.shadowSpread,
                cornerRadius: style.cornerRadius,
                stackLayout: scrollStackLayout(
                    layoutDirection: context.layoutDirection,
                    padding: context.contentInsets(for: .scrollContent, defaultInsets: style.padding),
                    alignmentAnchor: alignmentAnchor
                ),
                scrollStep: style.scrollStep,
                scrollIndicatorColor: style.indicatorColor,
                scrollIndicatorHoverColor: style.indicatorHoverColor,
                scrollIndicatorActiveColor: style.indicatorActiveColor,
                scrollIndicatorThickness: style.indicatorThickness,
                scrollIndicatorInsets: scrollIndicatorInsets,
                initialScrollAnchor: initialScrollAnchor,
                scrollSizeChangeAnchor: scrollSizeChangeAnchor,
                isHitTestVisible: style.isHitTestVisible,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
            if !context.isScrollEnabled {
                node.scrollAxis = nil
                node.showsScrollIndicator = false
            } else {
                node.showsScrollIndicator = (showsIndicators ?? true)
                    && context.scrollIndicatorVisibility(for: axis).showsRetainedScrollIndicator
            }
            if context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            return node
        }
    }

    private func scrollStackLayout(
        layoutDirection: LayoutDirection,
        padding: EdgeInsets,
        alignmentAnchor: UnitPoint?
    ) -> StackLayout {
        switch axis {
        case .horizontal:
            return .horizontal(
                spacing: style.spacing,
                padding: padding,
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.y) } ?? .center,
                mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.x) } ?? .start
            )
        case .vertical:
            return .vertical(
                spacing: style.spacing,
                padding: padding,
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.x) }
                    ?? style.alignment.stackAlignment(layoutDirection: layoutDirection),
                mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
            )
        }
    }
}

@MainActor
private enum ListSelectionMode {
    case single(get: () -> AnyHashable?, set: (AnyHashable?) -> Void)
    case multiple(get: () -> Set<AnyHashable>, set: (Set<AnyHashable>) -> Void)

    static func single<Value: Hashable>(_ selection: Binding<Value?>) -> ListSelectionMode {
        .single(
            get: {
                selection.wrappedValue.map { AnyHashable($0) }
            },
            set: { value in
                selection.wrappedValue = value?.base as? Value
            }
        )
    }

    static func requiredSingle<Value: Hashable>(_ selection: Binding<Value>) -> ListSelectionMode {
        .single(
            get: {
                AnyHashable(selection.wrappedValue)
            },
            set: { value in
                guard let value = value?.base as? Value else {
                    return
                }
                selection.wrappedValue = value
            }
        )
    }

    static func multiple<Value: Hashable>(_ selection: Binding<Set<Value>>) -> ListSelectionMode {
        .multiple(
            get: {
                Set(selection.wrappedValue.map { AnyHashable($0) })
            },
            set: { values in
                selection.wrappedValue = Set(values.compactMap { $0.base as? Value })
            }
        )
    }

    func contains(_ value: AnyHashable) -> Bool {
        switch self {
        case .single(let get, _):
            return get() == value
        case .multiple(let get, _):
            return get().contains(value)
        }
    }

    @discardableResult
    func activate(_ value: AnyHashable) -> Bool {
        switch self {
        case .single(let get, let set):
            guard get() != value else {
                return false
            }
            set(value)
            return true
        case .multiple(let get, let set):
            var values = get()
            if values.contains(value) {
                values.remove(value)
            } else {
                values.insert(value)
            }
            set(values)
            return true
        }
    }
}

@MainActor
public struct List: View {
    public typealias Body = Never

    private let content: [AnyView]
    private let selectionMode: ListSelectionMode?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.selectionMode = nil
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue?>?,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectionMode = selection.map { .single($0) }
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = ForEach(data, id: id, content: rowContent).contentViews
        self.selectionMode = nil
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<ID?>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: id, rowContent: rowContent)
        self.selectionMode = selection.map { .single($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<ID>>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: id, rowContent: rowContent)
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init(
        _ data: Range<Int>,
        selection: Binding<Int>,
        @ViewBuilder rowContent: (Int) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: \.self, rowContent: rowContent)
        self.selectionMode = .requiredSingle(selection)
    }

    public var body: Never {
        fatalError("List has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let listChrome = context.listStyle.retainedChrome
            let alignmentAnchor = context.defaultScrollAnchor(for: .alignment)
            let isEditing = context.environmentValues.editMode?.wrappedValue.isEditing == true
            let node = Controls.scrollPanel(
                axis: .vertical,
                backgroundColor: listChrome.backgroundColor,
                borderColor: listChrome.borderColor,
                borderWidth: listChrome.borderWidth,
                cornerRadius: listChrome.cornerRadius,
                stackLayout: .vertical(
                    spacing: context.listRowSpacing ?? listChrome.defaultSpacing,
                    padding: context.contentInsets(for: .scrollContent, defaultInsets: listChrome.padding),
                    alignment: .stretch,
                    mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
                ),
                isHitTestVisible: false,
                children: content.enumerated().map { pair in
                    let index = pair.offset
                    let view = pair.element
                    let tag = view.selectionTag
                    let isSelected = tag.map { selectionMode?.contains($0) == true } == true
                    let rowContext = isSelected
                        ? context.withEnvironmentValue(\.backgroundProminence, .increased)
                        : context
                    var row = view.makeComponent(context: rowContext).makeNode(runtime: runtime)
                    if let selectionMode, let tag {
                        row = Self.selectableRow(
                            wrapping: row,
                            tag: tag,
                            selectionMode: selectionMode,
                            isSelected: isSelected,
                            isEditing: isEditing,
                            context: context
                        )
                    }
                    row = Self.alternatingRowIfNeeded(
                        row,
                        index: index,
                        isSelected: isSelected,
                        listChrome: listChrome
                    )
                    if context.defaultMinListRowHeight > 0 {
                        row.applyDefaultMinimumHeight(context.defaultMinListRowHeight)
                    }
                    return row
                }
            )
            node.scrollIndicatorInsets = context.contentInsets(
                for: .scrollIndicators,
                defaultInsets: defaultRetainedScrollIndicatorInsets
            )
            node.initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
            node.scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
            if !context.isScrollEnabled {
                node.scrollAxis = nil
                node.showsScrollIndicator = false
            } else {
                node.showsScrollIndicator = context.verticalScrollIndicatorVisibility.showsRetainedScrollIndicator
            }
            if context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            return node
        }
    }

    private static func taggedRows<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        rowContent: (Data.Element) -> [AnyView]
    ) -> [AnyView] {
        var views: [AnyView] = []
        for element in data {
            let elementID = element[keyPath: id]
            let elementIDDescription = String(describing: elementID)
            let elementViews = rowContent(element)
            for (index, view) in elementViews.enumerated() {
                views.append(AnyView(view.id("\(elementIDDescription)#\(index)").tag(elementID)))
            }
        }
        return views
    }

    private static func selectableRow(
        wrapping row: ViewNode,
        tag: AnyHashable,
        selectionMode: ListSelectionMode,
        isSelected: Bool,
        isEditing: Bool,
        context: ViewBuildContext
    ) -> ViewNode {
        let selectionTint = context.tint
        if isEditing {
            row.layoutPriority = max(row.layoutPriority, 1)
        }
        let rowContent = isEditing
            ? Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(spacing: 10, padding: .zero, alignment: .center),
                isHitTestVisible: false,
                children: [
                    Self.editSelectionIndicator(isSelected: isSelected, tint: selectionTint),
                    row,
                ]
            )
            : row
        let rowNode = Controls.stackPanel(
            backgroundColor: isSelected ? selectionTint.opacity(0.16) : nil,
            borderColor: isSelected ? selectionTint.opacity(0.52) : .clear,
            borderWidth: isSelected ? 1 : 0,
            cornerRadius: 10,
            stackLayout: .vertical(
                spacing: 0,
                padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: [rowContent]
        )
        rowNode.nodeTag = row.nodeTag ?? "selection:\(String(describing: tag.base))"

        guard context.isEnabled else {
            return rowNode
        }

        rowNode.isFocusable = true
        rowNode.onActivate = {
            if selectionMode.activate(tag) {
                context.invalidate()
            }
        }
        return rowNode
    }

    private static func alternatingRowIfNeeded(
        _ row: ViewNode,
        index: Int,
        isSelected: Bool,
        listChrome: RetainedListChrome
    ) -> ViewNode {
        guard listChrome.alternatesRowBackgrounds,
              !isSelected,
              index % 2 == 1,
              row.backgroundColor == nil,
              row.backgroundGradient == nil,
              let backgroundColor = listChrome.alternatingRowBackgroundColor else {
            return row
        }

        row.backgroundColor = backgroundColor
        row.cornerRadius = max(row.cornerRadius, 8)
        return row
    }

    private static func editSelectionIndicator(isSelected: Bool, tint: Color) -> ViewNode {
        let innerNode = Controls.panel(
            preferredSize: Size(width: 8, height: 8),
            backgroundColor: isSelected ? .white : nil,
            cornerRadius: 4,
            isHitTestVisible: false
        )
        innerNode.nodeTag = "list-edit-selection-dot"

        let indicator = Controls.stackPanel(
            preferredSize: Size(width: 18, height: 18),
            backgroundColor: isSelected ? tint.opacity(0.92) : nil,
            borderColor: isSelected ? tint.opacity(0.96) : tint.opacity(0.46),
            borderWidth: 1,
            cornerRadius: 9,
            stackLayout: .vertical(alignment: .center, mainAlignment: .center),
            isHitTestVisible: false,
            children: isSelected ? [innerNode] : []
        )
        indicator.nodeTag = isSelected ? "list-edit-selection-selected" : "list-edit-selection-unselected"
        return indicator
    }
}

public extension List {
    init<Data: RandomAccessCollection>(
        _ data: Data,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.init(data, id: \.id, rowContent: rowContent)
    }

    init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<Data.Element.ID?>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.init(data, id: \.id, selection: selection, rowContent: rowContent)
    }

    init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<Set<Data.Element.ID>>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.init(data, id: \.id, selection: selection, rowContent: rowContent)
    }
}

private extension ViewNode {
    func applyDefaultMinimumHeight(_ minimumHeight: Double) {
        let resolvedMinimumHeight = max(0, minimumHeight)
        let constraints = layoutConstraints ?? .unconstrained
        layoutConstraints = LayoutConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth,
            minHeight: max(constraints.minHeight, resolvedMinimumHeight),
            maxHeight: max(constraints.maxHeight, resolvedMinimumHeight)
        )
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
            let chrome = Self.retainedChrome(for: context.formStyle)
            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                stackLayout: .vertical(spacing: chrome.spacing, padding: chrome.padding, alignment: .stretch),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }

    private struct RetainedChrome {
        var spacing: Double
        var padding: EdgeInsets
        var backgroundColor: Color?
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
    }

    private static func retainedChrome(for style: FormStyle) -> RetainedChrome {
        switch style.kind {
        case .automatic:
            return RetainedChrome(
                spacing: 12,
                padding: EdgeInsets.all(12),
                backgroundColor: nil,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0
            )
        case .columns:
            return RetainedChrome(
                spacing: 8,
                padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18),
                backgroundColor: nil,
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 8
            )
        case .grouped:
            return RetainedChrome(
                spacing: 10,
                padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.62),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 16
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
    private let isExpanded: Binding<Bool>?
    private let content: [AnyView]

    public init(
        _ title: String,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.footer = []
        self.style = style
        self.isExpanded = isExpanded
        self.content = content()
    }

    public init<S: StringProtocol>(
        _ title: S,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), isExpanded: isExpanded, style: style, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, isExpanded: isExpanded, style: style, content: content)
    }

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.header = []
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder footer: () -> [AnyView]
    ) {
        self.header = []
        self.footer = footer()
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Header: View>(
        header: Header,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [AnyView(header)]
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Footer: View>(
        footer: Footer,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = []
        self.footer = [AnyView(footer)]
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Header: View, Footer: View>(
        header: Header,
        footer: Footer,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [AnyView(header)]
        self.footer = [AnyView(footer)]
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = []
        self.style = .default
        self.isExpanded = isExpanded
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
        self.isExpanded = nil
        self.content = content()
    }

    public var body: Never {
        fatalError("Section has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let expansionBinding = isExpanded
        return Component { runtime in
            let headerFont = style.headerFont.resolvedHeaderFont(for: context.headerProminence)
            let headerContext = context
                .withForegroundColor(style.headerColor)
                .withFont(headerFont)
                .withTextAlignment(.leading)
                .withLineLimit(1)
            let footerContext = context
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.leading)

            let headerNodes = header.map {
                $0.makeComponent(context: headerContext).makeNode(runtime: runtime)
            }
            let resolvedHeaderNodes: [ViewNode]
            if let expansionBinding, !headerNodes.isEmpty {
                let chevronNode = Controls.label(
                    expansionBinding.wrappedValue ? "V" : ">",
                    preferredSize: Size(width: 18, height: 24),
                    color: style.headerColor,
                    scale: 1.2,
                    weight: .semibold,
                    lineBreakMode: .truncateTail,
                    maximumNumberOfLines: 1
                )
                let headerContent = Controls.stackPanel(
                    layoutPriority: 1,
                    stackLayout: .horizontal(spacing: 8, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .center),
                    isHitTestVisible: false,
                    children: [chevronNode] + headerNodes
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
                        expansionBinding.wrappedValue.toggle()
                        context.invalidate()
                    },
                    children: [headerContent]
                )
                resolvedHeaderNodes = [headerButton]
            } else {
                resolvedHeaderNodes = headerNodes
            }
            if let minimumHeaderHeight = context.defaultMinListHeaderHeight, minimumHeaderHeight > 0 {
                resolvedHeaderNodes.forEach { $0.applyDefaultMinimumHeight(minimumHeaderHeight) }
            }

            let contentNodes = expansionBinding?.wrappedValue == false
                ? []
                : content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            let children =
                resolvedHeaderNodes +
                contentNodes +
                footer.map { $0.makeComponent(context: footerContext).makeNode(runtime: runtime) }
            let hidesScrollContentBackground = style.scrollAxis != nil &&
                context.scrollContentBackgroundVisibility.hidesRetainedScrollContentBackground
            let alignmentAnchor = style.scrollAxis == nil ? nil : context.defaultScrollAnchor(for: .alignment)

            let node = Controls.stackPanel(
                backgroundColor: hidesScrollContentBackground ? nil : style.backgroundColor,
                backgroundGradient: hidesScrollContentBackground ? nil : style.backgroundGradient,
                borderColor: style.borderColor,
                borderWidth: 1,
                shadowColor: style.shadowColor,
                shadowOffset: Point(x: 0, y: 20),
                shadowSpread: 10,
                cornerRadius: style.cornerRadius,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: style.spacing,
                    padding: style.scrollAxis == nil
                        ? style.padding
                        : context.contentInsets(for: .scrollContent, defaultInsets: style.padding),
                    alignment: style.alignment.stackAlignment(layoutDirection: context.layoutDirection),
                    mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
                ),
                isHitTestVisible: style.isHitTestVisible,
                children: children
            )

            if context.isScrollEnabled, let axis = style.scrollAxis {
                node.scrollAxis = axis.scrollAxis
                node.scrollStep = style.scrollStep
                node.showsScrollIndicator = context.scrollIndicatorVisibility(for: axis).showsRetainedScrollIndicator
                node.scrollIndicatorInsets = context.contentInsets(
                    for: .scrollIndicators,
                    defaultInsets: defaultRetainedScrollIndicatorInsets
                )
                node.initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
                node.scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
                node.scrollIndicatorColor = style.indicatorColor
                node.scrollIndicatorIdleColor = style.indicatorColor
                node.scrollIndicatorHoverColor = style.indicatorHoverColor
                node.scrollIndicatorActiveColor = style.indicatorActiveColor
                node.scrollIndicatorThickness = style.indicatorThickness
            }
            if style.scrollAxis != nil, context.isScrollClipDisabled {
                node.clipsToBounds = false
            }

            return node
        }
    }
}

private extension Font {
    func resolvedHeaderFont(for prominence: Prominence) -> Font {
        switch prominence {
        case .standard:
            return self
        case .increased:
            return weight(.bold)
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

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
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

    public init<S: StringProtocol>(
        _ title: S,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), isExpanded: isExpanded, content: content)
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
    private let primaryAction: (@MainActor () -> Void)?

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(content: content, label: label, primaryAction: nil)
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(content: content, label: {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, content: content, primaryAction: primaryAction)
    }

    public init(_ title: String, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, image: name, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(content: content, label: {
            Label(title, image: name)
        }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), image: name, content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), image: name, content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: name, content: content)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, image: resource, content: content, primaryAction: nil)
    }

    public init<S: StringProtocol>(
        _ title: S,
        image resource: ImageResource,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(content: content, label: {
            Label(title, image: resource)
        }, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: resource, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image resource: ImageResource,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, image: resource, content: content, primaryAction: primaryAction)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, image: name, content: content, primaryAction: primaryAction)
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, systemImage: systemImage, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(content: content, label: {
            Label(title, systemImage: systemImage)
        }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), systemImage: systemImage, content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), systemImage: systemImage, content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content, primaryAction: primaryAction)
    }

    public var body: Never {
        fatalError("Menu has no body")
    }

    private func attachMenuDismiss(to node: ViewNode, dismiss: @escaping @MainActor () -> Void) {
        if let activate = node.onActivate {
            node.onActivate = {
                activate()
                dismiss()
            }
        }

        for child in node.children {
            attachMenuDismiss(to: child, dismiss: dismiss)
        }
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let menuState = state
        let menuItems = content
        let primaryAction = primaryAction
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let menuStyle = context.menuStyle
            let menuSurfaceStyle: ButtonSurfaceStyle
            let styleShowsMenuIndicator: Bool
            switch menuStyle.kind {
            case .borderlessButtonStyle(let showsMenuIndicator):
                menuSurfaceStyle = .plain
                styleShowsMenuIndicator = showsMenuIndicator
            case .borderedButtonStyle(let showsMenuIndicator):
                menuSurfaceStyle = .default
                styleShowsMenuIndicator = showsMenuIndicator
            case .automatic, .button:
                menuSurfaceStyle = .default
                styleShowsMenuIndicator = true
            }
            let showsMenuIndicator: Bool
            switch context.environmentValues.menuIndicatorVisibility {
            case .hidden:
                showsMenuIndicator = false
            case .visible:
                showsMenuIndicator = true
            case .automatic:
                showsMenuIndicator = styleShowsMenuIndicator
            }
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
            let headerChildren = showsMenuIndicator ? [labelNode, disclosureNode] : [labelNode]
            let headerContent = Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(spacing: 8, padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10), alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )
            let menuButton = Controls.button(
                runtime: runtime,
                cornerRadius: menuSurfaceStyle.cornerRadius,
                palette: menuSurfaceStyle.palette,
                chrome: menuSurfaceStyle.chrome,
                clipsToBounds: menuSurfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                animation: menuSurfaceStyle.animation,
                action: {
                    if let primaryAction {
                        primaryAction()
                    } else {
                        menuState.isOpen.toggle()
                    }
                    context.invalidate()
                },
                children: [headerContent]
            )

            let dismissMenu: @MainActor () -> Void = {
                guard menuState.isOpen else {
                    return
                }

                menuState.isOpen = false
                context.invalidate()
            }
            var children: [ViewNode] = [menuButton]
            if menuState.isOpen {
                let itemContext = context
                    .withButtonStyle(.plain)
                    .withEnvironmentValue(\.dismiss, DismissAction(handler: dismissMenu))
                    .withEnvironmentValue(\.isPresented, true)
                let itemNodes = menuItems.map { item -> ViewNode in
                    let node = item.makeComponent(context: itemContext).makeNode(runtime: runtime)
                    attachMenuDismiss(to: node, dismiss: dismissMenu)
                    return node
                }
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

            let root = Controls.panel(
                preferredSize: menuButton.intrinsicContentSize(),
                layoutMode: .absolute,
                isHitTestVisible: false,
                children: children
            )
            root.onLayout = { bounds in
                let buttonSize = menuButton.intrinsicContentSize()
                let buttonFrame = Rect(origin: .zero, size: buttonSize)
                if menuButton.frame != buttonFrame {
                    menuButton.frame = buttonFrame
                }

                guard children.count > 1 else {
                    return
                }

                let panel = children[1]
                let panelSize = panel.intrinsicContentSize()
                let x: Double
                switch context.layoutDirection {
                case .leftToRight:
                    x = 0
                case .rightToLeft:
                    x = max(0, buttonSize.width - panelSize.width)
                }
                let panelFrame = Rect(
                    x: x,
                    y: min(bounds.size.height, buttonSize.height + 4),
                    width: panelSize.width,
                    height: panelSize.height
                )
                if panel.frame != panelFrame {
                    panel.frame = panelFrame
                }
            }

            return root
        }
    }
}

@MainActor
public struct ControlGroup: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.label = []
        self.content = content()
    }

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init(_ title: String, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, image: name)
        }
    }

    public init<S: StringProtocol>(_ title: S, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), image: name, content: content)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: name, content: content)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, image: resource)
        }
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: resource, content: content)
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, systemImage: systemImage)
        }
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), systemImage: systemImage, content: content)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content)
    }

    public var body: Never {
        fatalError("ControlGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponents = label.map { $0.makeComponent(context: context) }
        let chrome = Self.retainedChrome(for: context.controlGroupStyle, tint: context.tint)
        let controlComponents = content.map { $0.makeComponent(context: context.withButtonStyle(chrome.childButtonStyle)) }

        return Component { runtime in
            var children = labelComponents.map { component in
                let node = component.makeNode(runtime: runtime)
                node.layoutPriority = max(node.layoutPriority, 1)
                return node
            }
            children += controlComponents.map { $0.makeNode(runtime: runtime) }

            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                stackLayout: .horizontal(
                    spacing: chrome.spacing,
                    padding: chrome.padding,
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private struct RetainedChrome {
        var backgroundColor: Color
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
        var spacing: Double
        var padding: EdgeInsets
        var childButtonStyle: ButtonStyle
    }

    private static func retainedChrome(for style: ControlGroupStyle, tint: Color) -> RetainedChrome {
        switch style.kind {
        case .automatic:
            return RetainedChrome(
                backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.72),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 10,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                childButtonStyle: .borderless
            )
        case .compactMenu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.17, alpha: 0.58),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 7,
                spacing: 2,
                padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4),
                childButtonStyle: .borderless
            )
        case .menu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.64),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.13),
                borderWidth: 1,
                cornerRadius: 12,
                spacing: 5,
                padding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7),
                childButtonStyle: .borderless
            )
        case .navigation:
            return RetainedChrome(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.62),
                borderColor: tint.opacity(0.24),
                borderWidth: 1,
                cornerRadius: 9,
                spacing: 3,
                padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5),
                childButtonStyle: .borderless
            )
        case .palette:
            return RetainedChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.50),
                borderColor: tint.opacity(0.34),
                borderWidth: 1,
                cornerRadius: 8,
                spacing: 2,
                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                childButtonStyle: .bordered
            )
        }
    }
}

@MainActor
public struct TextField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private let prompt: String?
    private let axis: Axis
    private let label: [AnyView]?
    private let onEditingChanged: (@MainActor (Bool) -> Void)?
    private let onCommit: (@MainActor () -> Void)?

    public init(_ title: String, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.title = title
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(String(title), text: text, prompt: prompt, axis: axis)
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(titleKey.resolvedString, text: text, prompt: prompt, axis: axis)
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = label()
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            titleKey.resolvedString,
            text: text,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.onEditingChanged = nil
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, text: text, onCommit: onCommit)
    }

    public var body: Never {
        fatalError("TextField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let allowsNewlines: Bool
        switch axis {
        case .horizontal:
            allowsNewlines = false
        case .vertical:
            allowsNewlines = true
        }
        return textInputComponent(
            title: label == nil ? (prompt ?? title) : prompt,
            text: text,
            isSecure: false,
            allowsNewlines: allowsNewlines,
            preferredSize: allowsNewlines ? context.controlSize.multilineTextInputSize : context.controlSize.singleLineTextInputSize,
            label: label,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit,
            context: context
        )
    }
}

@MainActor
public struct SecureField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private let prompt: String?
    private let label: [AnyView]?
    private let onCommit: (@MainActor () -> Void)?

    public init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title
        self.text = text
        self.prompt = prompt?.plainContent
        self.label = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) {
        self.init(String(title), text: text, prompt: prompt)
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) {
        self.init(titleKey.resolvedString, text: text, prompt: prompt)
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.label = label()
        self.onCommit = nil
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.label = nil
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, text: text, onCommit: onCommit)
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: label == nil ? (prompt ?? title) : prompt,
            text: text,
            isSecure: true,
            allowsNewlines: false,
            preferredSize: context.controlSize.singleLineTextInputSize,
            label: label,
            onEditingChanged: nil,
            onCommit: onCommit,
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
            preferredSize: context.controlSize.multilineTextInputSize,
            label: nil,
            onEditingChanged: nil,
            onCommit: nil,
            context: context
        )
    }
}

public extension View {
    func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        searchable(text: text, placement: placement, prompt: "Search")
    }

    func searchable<S: StringProtocol>(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: S
    ) -> some View {
        ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: nil,
                prompt: String(prompt),
                placement: placement
            )
        }
    }

    func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt.resolvedString)
    }

    func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt.plainContent)
    }

    func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: "Search")
    }

    func searchable<S: StringProtocol>(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: S
    ) -> some View {
        ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: isPresented,
                prompt: String(prompt),
                placement: placement
            )
        }
    }

    func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt.resolvedString)
    }

    func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt.plainContent)
    }
}

@MainActor
private func searchableComponent<Content: View>(
    content: Content,
    context: ViewBuildContext,
    text: Binding<String>,
    isPresented: Binding<Bool>?,
    prompt: String,
    placement: SearchFieldPlacement
) -> Component {
    let isSearching = isPresented?.wrappedValue ?? !text.wrappedValue.isEmpty
    let title = prompt.isEmpty ? "Search" : prompt
    let dismissSearch = DismissSearchAction {
        let isCurrentlySearching = isPresented?.wrappedValue ?? !text.wrappedValue.isEmpty
        guard isCurrentlySearching else {
            return
        }

        if !text.wrappedValue.isEmpty {
            text.wrappedValue = ""
        }
        if let isPresented, isPresented.wrappedValue {
            isPresented.wrappedValue = false
        }
        context.invalidate()
    }

    let searchContext = context
        .withEnvironmentValue(\.isSearching, isSearching)
        .withEnvironmentValue(\.dismissSearch, dismissSearch)
    let searchField = TextField(title, text: text)
        .submitLabel(.search)
        .makeComponent(context: searchContext)
    let child = content.makeComponent(context: searchContext)

    return Component { runtime in
        var children: [ViewNode] = []
        let showsSearchField = isPresented?.wrappedValue ?? true
        if showsSearchField {
            let searchNode = searchField.makeNode(runtime: runtime)
            applySearchPlacementChrome(to: searchNode, placement: placement, context: context)
            let existingOnFocusEnter = searchNode.onFocusEnter
            searchNode.onFocusEnter = {
                existingOnFocusEnter?()
                guard let isPresented, !isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = true
                context.invalidate()
            }
            let existingOnFocusExit = searchNode.onFocusExit
            searchNode.onFocusExit = {
                existingOnFocusExit?()
                applySearchPlacementChrome(to: searchNode, placement: placement, context: context)
            }
            children.append(searchNode)
        }

        children.append(child.makeNode(runtime: runtime))
        return Controls.stackPanel(
            stackLayout: .vertical(spacing: 8, alignment: .stretch),
            children: children
        )
    }
}

private struct RetainedSearchChrome {
    var nodeTag: String
    var preferredSize: Size?
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
}

@MainActor
private func applySearchPlacementChrome(
    to node: ViewNode,
    placement: SearchFieldPlacement,
    context: ViewBuildContext
) {
    guard let chrome = retainedSearchChrome(for: placement, context: context) else {
        return
    }

    node.nodeTag = chrome.nodeTag
    node.preferredSize = chrome.preferredSize ?? node.preferredSize
    node.backgroundColor = chrome.backgroundColor
    node.borderColor = chrome.borderColor
    node.borderWidth = chrome.borderWidth
    node.cornerRadius = chrome.cornerRadius
}

@MainActor
private func retainedSearchChrome(
    for placement: SearchFieldPlacement,
    context: ViewBuildContext
) -> RetainedSearchChrome? {
    if placement == .toolbar {
        return RetainedSearchChrome(
            nodeTag: "search-field-toolbar",
            preferredSize: Size(width: 240, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.92),
            borderColor: context.tint.opacity(0.26),
            borderWidth: 1,
            cornerRadius: 12
        )
    }

    if placement == .sidebar {
        return RetainedSearchChrome(
            nodeTag: "search-field-sidebar",
            preferredSize: Size(width: 210, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.17, alpha: 0.72),
            borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
            borderWidth: 1,
            cornerRadius: 8
        )
    }

    let isNavigationDrawer = placement == .navigationBarDrawer
        || placement == .navigationBarDrawer(displayMode: .automatic)
        || placement == .navigationBarDrawer(displayMode: .always)
    if isNavigationDrawer {
        return RetainedSearchChrome(
            nodeTag: "search-field-navigation-drawer",
            preferredSize: Size(width: 280, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.84),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            borderWidth: 1,
            cornerRadius: 10
        )
    }

    return nil
}

private extension ControlSize {
    var singleLineTextInputSize: Size {
        switch self {
        case .mini:
            return Size(width: 180, height: 28)
        case .small:
            return Size(width: 200, height: 32)
        case .regular:
            return Size(width: 220, height: 36)
        case .large:
            return Size(width: 260, height: 44)
        case .extraLarge:
            return Size(width: 300, height: 52)
        }
    }

    var multilineTextInputSize: Size {
        switch self {
        case .mini:
            return Size(width: 220, height: 88)
        case .small:
            return Size(width: 240, height: 104)
        case .regular:
            return Size(width: 260, height: 120)
        case .large:
            return Size(width: 300, height: 144)
        case .extraLarge:
            return Size(width: 340, height: 168)
        }
    }

    var togglePreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 44, height: 28)
        case .small:
            return Size(width: 48, height: 30)
        case .regular:
            return Size(width: 52, height: 32)
        case .large:
            return Size(width: 60, height: 38)
        case .extraLarge:
            return Size(width: 68, height: 44)
        }
    }

    var pickerMenuPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 30)
        case .small:
            return Size(width: 180, height: 32)
        case .regular:
            return Size(width: 200, height: 36)
        case .large:
            return Size(width: 232, height: 44)
        case .extraLarge:
            return Size(width: 264, height: 52)
        }
    }

    var stepperButtonPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 28, height: 24)
        case .small:
            return Size(width: 30, height: 26)
        case .regular:
            return Size(width: 34, height: 30)
        case .large:
            return Size(width: 40, height: 36)
        case .extraLarge:
            return Size(width: 46, height: 42)
        }
    }

    var sliderPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 22)
        case .small:
            return Size(width: 180, height: 24)
        case .regular:
            return Size(width: 200, height: 28)
        case .large:
            return Size(width: 240, height: 34)
        case .extraLarge:
            return Size(width: 280, height: 40)
        }
    }

    var progressPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 5)
        case .small:
            return Size(width: 180, height: 6)
        case .regular:
            return Size(width: 200, height: 8)
        case .large:
            return Size(width: 240, height: 10)
        case .extraLarge:
            return Size(width: 280, height: 12)
        }
    }

    var circularProgressPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 18, height: 18)
        case .small:
            return Size(width: 22, height: 22)
        case .regular:
            return Size(width: 28, height: 28)
        case .large:
            return Size(width: 34, height: 34)
        case .extraLarge:
            return Size(width: 40, height: 40)
        }
    }

    var colorSwatchPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 28, height: 22)
        case .small:
            return Size(width: 30, height: 24)
        case .regular:
            return Size(width: 34, height: 28)
        case .large:
            return Size(width: 40, height: 34)
        case .extraLarge:
            return Size(width: 46, height: 40)
        }
    }
}

@MainActor
private func textInputComponent(
    title: String?,
    text: Binding<String>,
    isSecure: Bool,
    allowsNewlines: Bool,
    preferredSize: Size,
    label: [AnyView]?,
    onEditingChanged: (@MainActor (Bool) -> Void)?,
    onCommit: (@MainActor () -> Void)?,
    context: ViewBuildContext
) -> Component {
    let binding = text
    let placeholder = title
    let labelViews = label
    return Component { runtime in
        let currentText = binding.wrappedValue
        let isShowingPlaceholder = currentText.isEmpty
        let resolvedPlaceholder = placeholder
            ?? labelViews.flatMap { retainedPlainText(from: $0, context: context, runtime: runtime) }
        let displayText = isSecure && !isShowingPlaceholder ? String(repeating: "*", count: currentText.count) : currentText
        let textColor: Color
        if !context.isEnabled {
            textColor = Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.78)
        } else if isShowingPlaceholder {
            textColor = Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 0.84)
        } else {
            textColor = context.foregroundColor
        }

        let resolvedFont = (context.fontWeight.map { context.font.weight($0) } ?? context.font)
            .scaled(for: context.dynamicTypeSize)

        let labelNode = Controls.label(
            isShowingPlaceholder ? (resolvedPlaceholder ?? "") : displayText,
            color: textColor,
            scale: resolvedFont.resolvedScale,
            weight: resolvedFont.weight.textWeight,
            fontFamily: resolvedFont.resolvedFamily,
            nativeFontSize: resolvedFont.resolvedNativeTextSize,
            alignment: context.textAlignment.textAlignment(layoutDirection: context.layoutDirection),
            insets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            lineSpacing: context.lineSpacing ?? resolvedFont.resolvedLineSpacing,
            lineBreakMode: allowsNewlines ? .wrap : .truncateTail,
            maximumNumberOfLines: allowsNewlines ? nil : 1
        )
        let style = context.textFieldStyle.resolvedTextInputStyle(isEnabled: context.isEnabled)
        let node = Controls.stackPanel(
            preferredSize: preferredSize,
            backgroundColor: style.backgroundColor,
            borderColor: style.borderColor,
            borderWidth: style.borderWidth,
            cornerRadius: style.cornerRadius,
            stackLayout: .vertical(padding: style.padding, alignment: .stretch),
            isHitTestVisible: context.isEnabled,
            children: [labelNode]
        )
        node.textInputSubmitLabel = context.submitLabel.retainedSubmitLabel
        node.textInputCaretOffset = currentText.count

        guard context.isEnabled else {
            return node
        }

        node.isFocusable = true
        node.onFocusEnter = { [weak node] in
            node?.borderColor = context.tint
            node?.outlineColor = context.tint.opacity(0.28)
            node?.outlineWidth = 2
            onEditingChanged?(true)
        }
        node.onFocusExit = { [weak node] in
            node?.borderColor = style.borderColor
            node?.outlineColor = .clear
            node?.outlineWidth = 0
            onEditingChanged?(false)
        }
        node.onKeyDown = { event in
            let clampedCaret = clampedTextOffset(node.textInputCaretOffset, in: binding.wrappedValue)

            if event.key == .enter, !allowsNewlines {
                if let onCommit {
                    onCommit()
                    context.invalidate()
                }
                return
            }

            if event.key == .backspace {
                guard clampedCaret > 0 else {
                    return
                }

                let updatedText = binding.wrappedValue.removingText(
                    in: (clampedCaret - 1)..<clampedCaret
                )
                binding.wrappedValue = updatedText
                node.textInputCaretOffset = clampedCaret - 1
                context.invalidate()
                return
            }

            if event.key == .deleteForward {
                guard clampedCaret < binding.wrappedValue.count else {
                    return
                }

                binding.wrappedValue = binding.wrappedValue.removingText(
                    in: clampedCaret..<(clampedCaret + 1)
                )
                node.textInputCaretOffset = clampedCaret
                context.invalidate()
                return
            }

            switch event.key {
            case .leftArrow:
                node.textInputCaretOffset = max(0, clampedCaret - 1)
                context.invalidate()
                return
            case .rightArrow:
                node.textInputCaretOffset = min(binding.wrappedValue.count, clampedCaret + 1)
                context.invalidate()
                return
            case .home:
                node.textInputCaretOffset = 0
                context.invalidate()
                return
            case .end:
                node.textInputCaretOffset = binding.wrappedValue.count
                context.invalidate()
                return
            case .backspace, .deleteForward:
                return
            case nil, .tab, .enter, .shift, .control, .alt, .escape, .pageUp, .pageDown, .upArrow, .downArrow, .space:
                break
            }

            guard let character = textFieldInsertedCharacter(
                for: event,
                allowsNewlines: allowsNewlines,
                currentText: binding.wrappedValue.textPrefix(upTo: clampedCaret),
                textInputAutocapitalization: context.textInputAutocapitalization
            ) else {
                return
            }

            binding.wrappedValue = binding.wrappedValue.insertingText(character, at: clampedCaret)
            node.textInputCaretOffset = clampedCaret + character.count
            context.invalidate()
        }

        return node
    }
}

@MainActor
private func retainedPlainText(
    from views: [AnyView],
    context: ViewBuildContext,
    runtime: RetainedViewRuntime
) -> String? {
    for view in views {
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        if let text = firstRetainedText(in: node), !text.isEmpty {
            return text
        }
    }
    return nil
}

@MainActor
private func firstRetainedText(in node: ViewNode) -> String? {
    let candidates = retainedTextCandidates(in: node)
    return candidates.preferred ?? candidates.fallback
}

@MainActor
private func retainedTextCandidates(in node: ViewNode) -> (preferred: String?, fallback: String?) {
    var fallback: String?
    if let text = node.text, !text.isEmpty {
        if node.textStyle.fontFamily != "Segoe Fluent Icons" {
            return (text, nil)
        }
        fallback = text
    }
    for child in node.children {
        let childCandidates = retainedTextCandidates(in: child)
        if let preferred = childCandidates.preferred {
            return (preferred, fallback ?? childCandidates.fallback)
        }
        fallback = fallback ?? childCandidates.fallback
    }
    return (nil, fallback)
}

public struct DatePickerComponents: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
    public static let date = DatePickerComponents(rawValue: 1 << 1)
    public static let all: DatePickerComponents = [.date, .hourAndMinute]
}

private struct DatePickerRange: Sendable {
    var lowerBound: Date?
    var upperBound: Date?
    var includesUpperBound: Bool

    static let unbounded = DatePickerRange(
        lowerBound: nil,
        upperBound: nil,
        includesUpperBound: true
    )

    init(
        lowerBound: Date? = nil,
        upperBound: Date? = nil,
        includesUpperBound: Bool = true
    ) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.includesUpperBound = includesUpperBound
    }

    func contains(_ date: Date) -> Bool {
        if let lowerBound, date < lowerBound {
            return false
        }
        if let upperBound {
            return includesUpperBound ? date <= upperBound : date < upperBound
        }
        return true
    }
}

@MainActor
public struct DatePicker: View {
    public typealias Body = Never

    private let selection: Binding<Date>
    private let displayedComponents: DatePickerComponents
    private let label: [AnyView]
    private let range: DatePickerRange

    public init(
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(selection: selection, displayedComponents: displayedComponents, range: .unbounded, label: label)
    }

    private init(
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents,
        range: DatePickerRange,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.displayedComponents = displayedComponents
        self.label = label()
        self.range = range
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(lowerBound: range.lowerBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(upperBound: range.upperBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(upperBound: range.upperBound, includesUpperBound: false),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public var body: Never {
        fatalError("DatePicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelViews = label
        let selection = selection
        let displayedComponents = displayedComponents
        let range = range
        let environmentValues = context.environmentValues
        let datePickerStyle = context.datePickerStyle
        var interactionCalendar = environmentValues.calendar
        interactionCalendar.timeZone = environmentValues.timeZone
        let labelComponent = composeComponent(
            from: labelViews,
            context: context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let valueNode = Text(Self.formattedValue(
                selection.wrappedValue,
                components: displayedComponents,
                calendar: environmentValues.calendar,
                timeZone: environmentValues.timeZone,
                locale: environmentValues.locale
            ))
                .monospaced()
                .lineLimit(1)
                .makeComponent(
                    context: context
                        .withTextAlignment(.trailing)
                        .withLineLimit(1)
                )
                .makeNode(runtime: runtime)
            valueNode.layoutPriority = max(valueNode.layoutPriority, 1)
            let controlNode = Self.retainedValueControl(
                for: valueNode,
                style: datePickerStyle,
                context: context
            )

            guard !context.labelsHidden, !labelViews.isEmpty else {
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    range: range,
                    components: displayedComponents,
                    calendar: interactionCalendar,
                    isEnabled: context.isEnabled,
                    invalidate: context.invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let node = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [labelNode, controlNode]
            )
            Self.configureInteraction(
                on: node,
                selection: selection,
                range: range,
                components: displayedComponents,
                calendar: interactionCalendar,
                isEnabled: context.isEnabled,
                invalidate: context.invalidate
            )
            return node
        }
    }

    private static func retainedValueControl(
        for valueNode: ViewNode,
        style: DatePickerStyle,
        context: ViewBuildContext
    ) -> ViewNode {
        switch style.kind {
        case .automatic:
            return valueNode
        case .compact:
            let disclosureNode = Controls.icon(
                .chevronDown,
                preferredSize: Size(width: 14, height: 14),
                color: context.foregroundColor.opacity(context.isEnabled ? 0.78 : 0.45),
                scale: 1.1
            )
            return Controls.stackPanel(
                preferredSize: context.controlSize.singleLineTextInputSize,
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.17, alpha: context.isEnabled ? 0.64 : 0.34),
                borderColor: context.tint.opacity(context.isEnabled ? 0.32 : 0.16),
                borderWidth: 1,
                cornerRadius: 8,
                stackLayout: .horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8),
                    alignment: .center
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode, disclosureNode]
            )
        case .field:
            return Controls.stackPanel(
                preferredSize: context.controlSize.singleLineTextInputSize,
                backgroundColor: Color(red: 0.05, green: 0.07, blue: 0.10, alpha: context.isEnabled ? 0.52 : 0.28),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.22 : 0.10),
                borderWidth: 1,
                cornerRadius: 3,
                stackLayout: .vertical(
                    padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode]
            )
        case .stepperField:
            let stepperNode = Controls.stackPanel(
                preferredSize: Size(width: 22, height: context.controlSize.singleLineTextInputSize.height),
                backgroundColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.08 : 0.04),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 4,
                stackLayout: .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: [
                    Controls.label("+", color: context.foregroundColor.opacity(context.isEnabled ? 0.70 : 0.38), scale: 1.0),
                    Controls.label("-", color: context.foregroundColor.opacity(context.isEnabled ? 0.70 : 0.38), scale: 1.0)
                ]
            )
            return Controls.stackPanel(
                preferredSize: Size(
                    width: context.controlSize.singleLineTextInputSize.width + 30,
                    height: context.controlSize.singleLineTextInputSize.height
                ),
                backgroundColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: context.isEnabled ? 0.58 : 0.30),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.24 : 0.11),
                borderWidth: 1,
                cornerRadius: 7,
                stackLayout: .horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 4),
                    alignment: .center
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode, stepperNode]
            )
        case .wheel:
            let guideColor = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.14 : 0.07)
            let topGuide = Controls.panel(
                preferredSize: Size(width: 1, height: 7),
                backgroundColor: guideColor,
                isHitTestVisible: false
            )
            let bottomGuide = Controls.panel(
                preferredSize: Size(width: 1, height: 7),
                backgroundColor: guideColor,
                isHitTestVisible: false
            )
            return Controls.stackPanel(
                preferredSize: Size(width: context.controlSize.singleLineTextInputSize.width, height: 64),
                backgroundColor: Color(red: 0.07, green: 0.09, blue: 0.13, alpha: context.isEnabled ? 0.60 : 0.30),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.18 : 0.08),
                borderWidth: 1,
                cornerRadius: 10,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: 4,
                    padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [topGuide, valueNode, bottomGuide]
            )
        case .graphical:
            let headerLine = Controls.panel(
                preferredSize: Size(width: 1, height: 2),
                backgroundColor: context.tint.opacity(context.isEnabled ? 0.34 : 0.16),
                cornerRadius: 1,
                isHitTestVisible: false
            )
            let gridHint = Controls.stackPanel(
                backgroundColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.05 : 0.02),
                cornerRadius: 5,
                stackLayout: .horizontal(
                    spacing: 3,
                    padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: (0..<5).map { index in
                    Controls.panel(
                        preferredSize: Size(width: 10, height: 10),
                        backgroundColor: index == 2
                            ? context.tint.opacity(context.isEnabled ? 0.62 : 0.26)
                            : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.10 : 0.04),
                        cornerRadius: 3,
                        isHitTestVisible: false
                    )
                }
            )
            return Controls.stackPanel(
                preferredSize: Size(width: context.controlSize.singleLineTextInputSize.width, height: 78),
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: context.isEnabled ? 0.68 : 0.34),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.18 : 0.08),
                borderWidth: 1,
                cornerRadius: 12,
                stackLayout: .vertical(
                    spacing: 7,
                    padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [headerLine, valueNode, gridHint]
            )
        }
    }

    private static func configureInteraction(
        on node: ViewNode,
        selection: Binding<Date>,
        range: DatePickerRange,
        components: DatePickerComponents,
        calendar: Calendar,
        isEnabled: Bool,
        invalidate: @escaping () -> Void
    ) {
        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.onKeyDown = { event in
            let direction: Int
            switch event.key {
            case .upArrow, .rightArrow:
                direction = 1
            case .downArrow, .leftArrow:
                direction = -1
            default:
                return
            }

            guard let proposedDate = steppedDate(
                from: selection.wrappedValue,
                direction: direction,
                components: components,
                calendar: calendar
            ), range.contains(proposedDate) else {
                return
            }

            selection.wrappedValue = proposedDate
            invalidate()
        }
    }

    private static func steppedDate(
        from date: Date,
        direction: Int,
        components: DatePickerComponents,
        calendar: Calendar
    ) -> Date? {
        let component: Calendar.Component = components == .date ? .day : .minute
        return calendar.date(byAdding: component, value: direction, to: date)
    }

    private static func formattedValue(
        _ date: Date,
        components: DatePickerComponents,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        if locale.identifier != Locale.current.identifier {
            return localizedFormattedValue(
                date,
                components: components,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let dateText = String(
            format: "%04d-%02d-%02d",
            dateComponents.year ?? 0,
            dateComponents.month ?? 1,
            dateComponents.day ?? 1
        )
        let timeText = String(
            format: "%02d:%02d",
            dateComponents.hour ?? 0,
            dateComponents.minute ?? 0
        )

        if components.contains(.date), components.contains(.hourAndMinute) {
            return "\(dateText) \(timeText)"
        }
        if components.contains(.date) {
            return dateText
        }
        if components.contains(.hourAndMinute) {
            return timeText
        }
        return dateText
    }

    private static func localizedFormattedValue(
        _ date: Date,
        components: DatePickerComponents,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale

        if components.contains(.date), components.contains(.hourAndMinute) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        } else if components.contains(.date) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        } else if components.contains(.hourAndMinute) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }

        return formatter.string(from: date)
    }
}

@MainActor
public struct ColorPicker: View {
    public typealias Body = Never

    private let selection: Binding<Color>
    private let supportsOpacity: Bool
    private let label: [AnyView]

    public init(
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(titleKey.resolvedString, selection: selection, supportsOpacity: supportsOpacity)
    }

    public var body: Never {
        fatalError("ColorPicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelViews = label
        let selection = selection
        let supportsOpacity = supportsOpacity
        let labelComponent = composeComponent(
            from: labelViews,
            context: context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let color = selection.wrappedValue
            let swatchNode = Controls.panel(
                preferredSize: context.controlSize.colorSwatchPreferredSize,
                backgroundColor: color,
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.30),
                borderWidth: 1,
                cornerRadius: 6,
                isHitTestVisible: false
            )
            let valueNode = Text(Self.hexValue(color, includesOpacity: supportsOpacity))
                .monospaced()
                .lineLimit(1)
                .makeComponent(
                    context: context
                        .withTextAlignment(.trailing)
                        .withLineLimit(1)
                )
                .makeNode(runtime: runtime)
            let controlNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [swatchNode, valueNode]
            )

            guard !context.labelsHidden, !labelViews.isEmpty else {
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    supportsOpacity: supportsOpacity,
                    isEnabled: context.isEnabled,
                    invalidate: context.invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let node = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [labelNode, controlNode]
            )
            Self.configureInteraction(
                on: node,
                selection: selection,
                supportsOpacity: supportsOpacity,
                isEnabled: context.isEnabled,
                invalidate: context.invalidate
            )
            return node
        }
    }

    private static func configureInteraction(
        on node: ViewNode,
        selection: Binding<Color>,
        supportsOpacity: Bool,
        isEnabled: Bool,
        invalidate: @escaping () -> Void
    ) {
        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.onActivate = {
            applyPaletteStep(to: selection, direction: 1, supportsOpacity: supportsOpacity, invalidate: invalidate)
        }
        node.onKeyDown = { event in
            switch event.key {
            case .rightArrow:
                applyPaletteStep(to: selection, direction: 1, supportsOpacity: supportsOpacity, invalidate: invalidate)
            case .leftArrow:
                applyPaletteStep(to: selection, direction: -1, supportsOpacity: supportsOpacity, invalidate: invalidate)
            case .upArrow where supportsOpacity:
                applyOpacityStep(to: selection, direction: 1, invalidate: invalidate)
            case .downArrow where supportsOpacity:
                applyOpacityStep(to: selection, direction: -1, invalidate: invalidate)
            default:
                return
            }
        }
    }

    private static func applyPaletteStep(
        to selection: Binding<Color>,
        direction: Int,
        supportsOpacity: Bool,
        invalidate: () -> Void
    ) {
        let currentColor = selection.wrappedValue
        let nextColor = steppedPaletteColor(from: currentColor, direction: direction, preservesOpacity: supportsOpacity)
        guard nextColor != currentColor else {
            return
        }

        selection.wrappedValue = nextColor
        invalidate()
    }

    private static func applyOpacityStep(
        to selection: Binding<Color>,
        direction: Int,
        invalidate: () -> Void
    ) {
        let currentColor = selection.wrappedValue
        let currentComponents = currentColor.rgba
        let nextAlpha = Float(clampedUnitIntervalValue(Double(currentComponents.3) + (Double(direction) * 0.10)))
        guard nextAlpha != currentComponents.3 else {
            return
        }

        selection.wrappedValue = Color(
            red: currentComponents.0,
            green: currentComponents.1,
            blue: currentComponents.2,
            alpha: nextAlpha
        )
        invalidate()
    }

    private static func steppedPaletteColor(from color: Color, direction: Int, preservesOpacity: Bool) -> Color {
        let palette = retainedKeyboardPalette
        guard !palette.isEmpty else {
            return color
        }

        let baseIndex = nearestPaletteIndex(to: color, in: palette)
        let nextIndex = (baseIndex + direction + palette.count) % palette.count
        let nextBaseColor = palette[nextIndex]
        let alpha = preservesOpacity ? color.rgba.3 : 1
        return nextBaseColor.opacity(Double(alpha))
    }

    private static func nearestPaletteIndex(to color: Color, in palette: [Color]) -> Int {
        let components = color.rgba
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

        for (index, paletteColor) in palette.enumerated() {
            let paletteComponents = paletteColor.rgba
            let redDistance = Double(components.0 - paletteComponents.0)
            let greenDistance = Double(components.1 - paletteComponents.1)
            let blueDistance = Double(components.2 - paletteComponents.2)
            let distance = (redDistance * redDistance) + (greenDistance * greenDistance) + (blueDistance * blueDistance)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static let retainedKeyboardPalette: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink,
        .brown,
        .gray,
        .black,
        .white,
    ]

    private static func clampedUnitIntervalValue(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func hexValue(_ color: Color, includesOpacity: Bool) -> String {
        let components = color.rgba
        let alphaText = includesOpacity ? String(format: "%02X", byte(from: components.3)) : ""
        return String(
            format: "#%02X%02X%02X%@",
            byte(from: components.0),
            byte(from: components.1),
            byte(from: components.2),
            alphaText
        )
    }

    private static func byte(from channel: Float) -> Int {
        let clampedChannel = min(max(Double(channel), 0), 1)
        return Int((clampedChannel * 255).rounded())
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

    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(String(title), isOn: isOn)
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
            switch context.toggleStyle.kind {
            case .automatic, .switch:
                return Self.switchNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            case .checkbox:
                return Self.checkboxNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            case .button:
                return Self.buttonNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            }
        }
    }

    private static func switchNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let toggleNode = Controls.toggle(
            runtime: runtime,
            isOn: binding.wrappedValue,
            isEnabled: context.isEnabled,
            preferredSize: context.controlSize.togglePreferredSize,
            onColor: context.tint,
            onToggle: { newValue in
                binding.wrappedValue = newValue
                context.invalidate()
            }
        )

        guard !context.labelsHidden else {
            return toggleNode
        }

        let labelNode = labelComponent.makeNode(runtime: runtime)
        return Controls.stackPanel(
            stackLayout: .horizontal(spacing: 10, alignment: .center),
            isHitTestVisible: false,
            children: [labelNode, toggleNode]
        )
    }

    private static func checkboxNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let boxSize: Double = 20
        let surfaceStyle = ButtonSurfaceStyle.default
        let checkIcon = binding.wrappedValue
            ? Controls.icon(
                .checkmark,
                preferredSize: Size(width: boxSize - 4, height: boxSize - 4),
                color: context.isEnabled ? .white : surfaceStyle.palette.disabledForeground,
                scale: 1.2
            )
            : Controls.panel(
                preferredSize: Size(width: boxSize - 4, height: boxSize - 4),
                isHitTestVisible: false
            )
        let box = Controls.panel(
            preferredSize: Size(width: boxSize, height: boxSize),
            backgroundColor: context.isEnabled
                ? (binding.wrappedValue ? context.tint : surfaceStyle.palette.idle)
                : surfaceStyle.palette.disabledBackground,
            borderColor: context.isEnabled
                ? (binding.wrappedValue ? context.tint.opacity(0.92) : surfaceStyle.chrome.borderColor)
                : surfaceStyle.palette.disabledBorder,
            borderWidth: 1,
            cornerRadius: 4,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false,
            children: [checkIcon]
        )
        let children = context.labelsHidden
            ? [box]
            : [box, labelComponent.makeNode(runtime: runtime)]
        let hiddenPreferredSize = Size(
            width: max(context.controlSize.togglePreferredSize.height, boxSize + 16),
            height: max(context.controlSize.togglePreferredSize.height, boxSize + 16)
        )

        return Controls.button(
            runtime: runtime,
            preferredSize: context.labelsHidden ? hiddenPreferredSize : nil,
            cornerRadius: 8,
            palette: SurfacePalette(
                idle: .clear,
                hovered: Color(red: 0.20, green: 0.26, blue: 0.34, alpha: 0.44),
                focused: Color(red: 0.24, green: 0.32, blue: 0.42, alpha: 0.56),
                pressed: Color(red: 0.30, green: 0.40, blue: 0.52, alpha: 0.64),
                activated: Color(red: 0.30, green: 0.40, blue: 0.52, alpha: 0.64)
            ),
            chrome: SurfaceChrome(
                borderColor: .clear,
                borderHoveredColor: Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.16),
                borderFocusedColor: context.tint.opacity(0.42),
                borderPressedColor: context.tint.opacity(0.58),
                borderWidth: 1,
                focusRingColor: context.tint.opacity(0.26),
                focusRingWidth: 2
            ),
            clipsToBounds: true,
            layoutMode: .stack(
                .horizontal(
                    spacing: context.labelsHidden ? 0 : 10,
                    padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 8),
                    alignment: .center
                )
            ),
            isEnabled: context.isEnabled,
            action: {
                binding.wrappedValue.toggle()
                context.invalidate()
            },
            children: children
        )
    }

    private static func buttonNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let surfaceStyle = ButtonSurfaceStyle.default
        let palette = binding.wrappedValue
            ? SurfacePalette(
                idle: context.tint.opacity(0.82),
                hovered: context.tint.opacity(0.90),
                focused: context.tint.opacity(0.96),
                pressed: context.tint,
                activated: context.tint
            )
            : surfaceStyle.palette
        let children: [ViewNode]
        if context.labelsHidden {
            let iconNode = binding.wrappedValue
                ? Controls.icon(
                    .checkmark,
                    preferredSize: Size(width: 20, height: 20),
                    color: context.isEnabled ? .white : surfaceStyle.palette.disabledForeground,
                    scale: 1.25
                )
                : Controls.panel(
                    preferredSize: Size(width: 20, height: 20),
                    isHitTestVisible: false
                )
            children = [
                iconNode
            ]
        } else {
            children = [labelComponent.makeNode(runtime: runtime)]
        }
        let hiddenPreferredSize = Size(
            width: max(context.controlSize.togglePreferredSize.width, 44),
            height: max(context.controlSize.togglePreferredSize.height, 36)
        )

        return Controls.button(
            runtime: runtime,
            preferredSize: context.labelsHidden ? hiddenPreferredSize : nil,
            cornerRadius: surfaceStyle.cornerRadius,
            palette: palette,
            chrome: surfaceStyle.chrome,
            clipsToBounds: surfaceStyle.clipsToBounds,
            layoutMode: .stack(
                .horizontal(
                    spacing: 0,
                    padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                    alignment: .center,
                    mainAlignment: .center
                )
            ),
            isEnabled: context.isEnabled,
            animation: surfaceStyle.animation,
            action: {
                binding.wrappedValue.toggle()
                context.invalidate()
            },
            children: children
        )
    }
}

@MainActor
public struct Picker<SelectionValue: Hashable>: View {
    public typealias Body = Never

    private let selection: Binding<SelectionValue>
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]
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
        self.currentValueLabel = []
        self.content = content()
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), selection: selection, content: content)
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
        self.currentValueLabel = []
        self.content = content()
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
        self.currentValueLabel = []
        self.content = content()
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.content = content()
    }

    public var body: Never {
        fatalError("Picker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let selection = selection
        let labelViews = label
        let currentValueLabelViews = currentValueLabel
        let contentViews = content
        let labelComponent = composeComponent(
            from: labelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let currentValueLabelComponent = composeComponent(
            from: currentValueLabelViews,
            context: context
                .withTextAlignment(.trailing)
                .withLineLimit(1),
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
            case .inline:
                pickerNode = Self.inlinePickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .navigationLink:
                pickerNode = Self.navigationLinkPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    options: options
                )
            case .palette:
                pickerNode = Self.palettePickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .radioGroup:
                pickerNode = Self.radioGroupPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .wheel:
                pickerNode = Self.wheelPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .menu, .popUpButton:
                pickerNode = Self.menuPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    options: options
                )
            }

            guard !context.labelsHidden && (!labelViews.isEmpty || !currentValueLabelViews.isEmpty) else {
                return pickerNode
            }

            guard !currentValueLabelViews.isEmpty else {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, pickerNode]
                )
            }

            var headerChildren: [ViewNode] = []
            if !labelViews.isEmpty {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
                headerChildren.append(labelNode)
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
                children: [headerNode, pickerNode]
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

    private static func inlinePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let indicatorNode = isSelected
                ? Controls.icon(
                    .checkmark,
                    preferredSize: Size(width: 18, height: 18),
                    color: context.isEnabled ? context.tint : Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.70),
                    scale: 1.2
                )
                : Controls.panel(
                    preferredSize: Size(width: 18, height: 18),
                    isHitTestVisible: false
                )
            option.node.layoutPriority = max(option.node.layoutPriority, 1)

            return Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 6,
                palette: SurfacePalette(
                    idle: isSelected
                        ? context.tint.opacity(0.14)
                        : Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.34),
                    hovered: isSelected
                        ? context.tint.opacity(0.22)
                        : Color(red: 0.18, green: 0.24, blue: 0.32, alpha: 0.54),
                    focused: isSelected
                        ? context.tint.opacity(0.28)
                        : Color(red: 0.22, green: 0.30, blue: 0.40, alpha: 0.64),
                    pressed: isSelected
                        ? context.tint.opacity(0.34)
                        : Color(red: 0.28, green: 0.38, blue: 0.50, alpha: 0.72)
                ),
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.36) : .clear,
                    borderHoveredColor: isSelected ? context.tint.opacity(0.50) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                    borderFocusedColor: context.tint.opacity(0.64),
                    borderPressedColor: context.tint.opacity(0.72),
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: context.tint.opacity(0.26),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(.horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 10),
                    alignment: .center
                )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [indicatorNode, option.node]
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.46),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 10,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 2,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func navigationLinkPickerNode(
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
            preferredSize: Size(
                width: context.controlSize.pickerMenuPreferredSize.width + 24,
                height: context.controlSize.pickerMenuPreferredSize.height + 4
            ),
            palette: SurfacePalette(
                idle: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.52),
                hovered: Color(red: 0.13, green: 0.18, blue: 0.26, alpha: 0.64),
                focused: Color(red: 0.17, green: 0.24, blue: 0.34, alpha: 0.76),
                pressed: Color(red: 0.22, green: 0.31, blue: 0.44, alpha: 0.84)
            ),
            chrome: SurfaceChrome(
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderHoveredColor: context.tint.opacity(0.36),
                borderFocusedColor: context.tint.opacity(0.54),
                borderPressedColor: context.tint.opacity(0.66),
                borderWidth: 1,
                focusRingColor: context.tint.opacity(0.26),
                focusRingWidth: 2
            ),
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
    }

    private static func palettePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let itemHeight = context.controlSize.pickerMenuPreferredSize.height
        let itemSize = Size(width: max(44, itemHeight * 1.45), height: itemHeight)
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette
            return Controls.button(
                runtime: runtime,
                preferredSize: itemSize,
                layoutPriority: 1,
                cornerRadius: 10,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.62) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
                    borderHoveredColor: isSelected ? context.tint.opacity(0.78) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
                    borderFocusedColor: isSelected ? context.tint.opacity(0.88) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.30),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.36),
                    borderWidth: isSelected ? 2 : 1,
                    focusRingColor: context.tint.opacity(0.30),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(.vertical(
                    padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
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
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.72),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func wheelPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let itemHeight = max(1, Double(context.environmentValues.defaultWheelPickerItemHeight))
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette
            let optionNode = Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.48) : .clear,
                    borderHoveredColor: isSelected ? context.tint.opacity(0.64) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderFocusedColor: isSelected ? context.tint.opacity(0.78) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.24),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(.vertical(
                    padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12),
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
                children: [
                    Controls.label(
                        title,
                        layoutPriority: 1,
                        color: isSelected ? .white : .secondary,
                        scale: 1.6,
                        weight: isSelected ? .semibold : .regular,
                        alignment: .center,
                        lineBreakMode: .truncateTail,
                        maximumNumberOfLines: 1
                    )
                ]
            )
            optionNode.applyDefaultMinimumHeight(itemHeight)
            return optionNode
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.68),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 2,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func radioGroupPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            return Controls.radioButton(
                runtime: runtime,
                label: title,
                isSelected: isSelected,
                isEnabled: context.isEnabled && option.value != nil,
                layoutPriority: 1,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.40) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderHoveredColor: isSelected ? context.tint.opacity(0.58) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
                    borderFocusedColor: isSelected ? context.tint.opacity(0.72) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.26),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                selectedColor: context.tint,
                onSelect: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                }
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.72),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
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
            preferredSize: context.controlSize.pickerMenuPreferredSize,
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
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(
        _ title: S,
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            String(title),
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            titleKey.resolvedString,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init(
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.canDecrement = {
            onDecrement != nil
        }
        self.canIncrement = {
            onIncrement != nil
        }
        self.decrement = {
            guard let onDecrement else {
                return
            }
            onEditingChanged(true)
            onDecrement()
            onEditingChanged(false)
        }
        self.increment = {
            guard let onIncrement else {
                return
            }
            onEditingChanged(true)
            onIncrement()
            onEditingChanged(false)
        }
    }

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

    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(String(title), value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
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

    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(String(title), value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
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
            let decrementNode = Self.controlButton(
                runtime: runtime,
                title: "-",
                isEnabled: context.isEnabled && canDecrement(),
                preferredSize: context.controlSize.stepperButtonPreferredSize,
                action: {
                    decrement()
                    context.invalidate()
                }
            )
            let incrementNode = Self.controlButton(
                runtime: runtime,
                title: "+",
                isEnabled: context.isEnabled && canIncrement(),
                preferredSize: context.controlSize.stepperButtonPreferredSize,
                action: {
                    increment()
                    context.invalidate()
                }
            )

            guard !context.labelsHidden else {
                return Controls.stackPanel(
                    stackLayout: .horizontal(spacing: 8, alignment: .center),
                    isHitTestVisible: false,
                    children: [decrementNode, incrementNode]
                )
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
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
        preferredSize: Size,
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
            preferredSize: preferredSize,
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

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
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
                preferredSize: context.controlSize.sliderPreferredSize,
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

            guard !context.labelsHidden else {
                return sliderNode
            }

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

    public init<S: StringProtocol>(_ title: S, value: Double? = nil, total: Double = 1.0) {
        self.init(String(title), value: value, total: total)
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

    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
        self.label = []
        self.currentValueLabel = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
        self.label = label()
        self.currentValueLabel = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
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
            let progressNode: ViewNode
            switch context.progressViewStyle.kind {
            case .circular:
                progressNode = Controls.circularProgress(
                    value: value,
                    total: total,
                    preferredSize: context.controlSize.circularProgressPreferredSize,
                    filledColor: context.tint
                )
            case .automatic, .linear:
                progressNode = Controls.progressBar(
                    value: value ?? 0,
                    total: total,
                    preferredSize: context.controlSize.progressPreferredSize,
                    filledColor: context.tint
                )
            }
            guard !context.labelsHidden else {
                return progressNode
            }

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

    private static func timerProgressValue(timerInterval: ClosedRange<Date>, countsDown: Bool) -> Double {
        let duration = timerInterval.upperBound.timeIntervalSince(timerInterval.lowerBound)
        guard duration > 0, duration.isFinite else {
            return countsDown ? 0 : 1
        }

        let elapsed = Date().timeIntervalSince(timerInterval.lowerBound)
        let progress = min(max(elapsed / duration, 0), 1)
        return countsDown ? 1 - progress : progress
    }
}

@MainActor
public struct Gauge: View {
    public typealias Body = Never

    private let value: Double
    private let bounds: ClosedRange<Double>
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]
    private let minimumValueLabel: [AnyView]
    private let maximumValueLabel: [AnyView]
    private let markedValueLabels: [AnyView]

    public init(value: Double, in bounds: ClosedRange<Double> = 0...1, @ViewBuilder label: () -> [AnyView]) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init(_ title: String, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.value = value
        self.bounds = bounds
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.5, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(_ title: String, value: V, in bounds: ClosedRange<V> = 0...1) {
        self.init(title, value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init<S: StringProtocol>(_ title: S, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.init(String(title), value: value, in: bounds)
    }

    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(String(title), value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init(_ titleKey: LocalizedStringKey, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.init(titleKey.resolvedString, value: value, in: bounds)
    }

    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(titleKey.resolvedString, value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init(
        value: Double,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder markedValueLabels: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = markedValueLabels()
    }

    public init(
        value: Double,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        @ViewBuilder markedValueLabels: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = markedValueLabels()
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = []
    }

    public var body: Never {
        fatalError("Gauge has no body")
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
        let minimumValueLabelComponent = composeComponent(
            from: minimumValueLabel,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .leading)),
            isHitTestVisible: false
        )
        let maximumValueLabelComponent = composeComponent(
            from: maximumValueLabel,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .trailing)),
            isHitTestVisible: false
        )
        let markedValueLabelsComponent = composeComponent(
            from: markedValueLabels,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let rangeTotal = max(0, bounds.upperBound - bounds.lowerBound)
            let gaugeValue = value - bounds.lowerBound
            let gaugeNode: ViewNode
            switch context.gaugeStyle.kind {
            case .circular, .accessoryCircular, .accessoryCircularCapacity:
                gaugeNode = Controls.circularProgress(
                    value: gaugeValue,
                    total: rangeTotal,
                    preferredSize: context.controlSize.circularProgressPreferredSize,
                    filledColor: context.tint
                )
            case .automatic, .linear, .linearCapacity, .accessoryLinear, .accessoryLinearCapacity:
                gaugeNode = Controls.progressBar(
                    value: gaugeValue,
                    total: rangeTotal,
                    preferredSize: context.controlSize.progressPreferredSize,
                    filledColor: context.tint
                )
            }
            guard !context.labelsHidden else {
                return gaugeNode
            }

            let hasHeader = !label.isEmpty || !currentValueLabel.isEmpty
            let hasBounds = !minimumValueLabel.isEmpty || !maximumValueLabel.isEmpty
            let hasMarkedLabels = !markedValueLabels.isEmpty
            guard hasHeader || hasBounds || hasMarkedLabels else {
                return gaugeNode
            }

            var children: [ViewNode] = []
            if hasHeader {
                var headerChildren: [ViewNode] = []
                if !label.isEmpty {
                    headerChildren.append(labelComponent.makeNode(runtime: runtime))
                }
                if !currentValueLabel.isEmpty {
                    headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))
                }

                children.append(
                    Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 8, alignment: .center),
                        isHitTestVisible: false,
                        children: headerChildren
                    )
                )
            }

            children.append(gaugeNode)

            if hasMarkedLabels {
                children.append(markedValueLabelsComponent.makeNode(runtime: runtime))
            }

            if hasBounds {
                var boundsChildren: [ViewNode] = []
                if !minimumValueLabel.isEmpty {
                    boundsChildren.append(minimumValueLabelComponent.makeNode(runtime: runtime))
                }
                boundsChildren.append(Controls.panel(layoutPriority: 1, isHitTestVisible: false))
                if !maximumValueLabel.isEmpty {
                    boundsChildren.append(maximumValueLabelComponent.makeNode(runtime: runtime))
                }

                children.append(
                    Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 8, alignment: .center),
                        isHitTestVisible: false,
                        children: boundsChildren
                    )
                )
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private static func doubleBounds<V: BinaryFloatingPoint>(_ bounds: ClosedRange<V>) -> ClosedRange<Double> {
        Double(bounds.lowerBound)...Double(bounds.upperBound)
    }
}

@MainActor
public struct Link: View {
    public typealias Body = Never

    private let destination: URL
    private let label: [AnyView]

    public init(destination: URL, @ViewBuilder label: () -> [AnyView]) {
        self.destination = destination
        self.label = label()
    }

    public init(_ title: String, destination: URL) {
        self.destination = destination
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
    }

    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.init(String(title), destination: destination)
    }

    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.init(titleKey.resolvedString, destination: destination)
    }

    public var body: Never {
        fatalError("Link has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context
                .withForegroundColor(context.tint)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )
        let openURL = context.environmentValues.openURL
        let destination = destination

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.button(
                runtime: runtime,
                cornerRadius: ButtonSurfaceStyle.plain.cornerRadius,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                clipsToBounds: ButtonSurfaceStyle.plain.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                animation: ButtonSurfaceStyle.plain.animation,
                action: {
                    _ = openURL(destination)
                    context.invalidate()
                },
                children: [labelNode]
            )
        }
    }
}

@MainActor
public struct RenameButton: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("RenameButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let rename = context.environmentValues.rename
        return Button("Rename") {
            rename?()
        }
        .disabled(rename == nil)
        .makeComponent(context: context)
    }
}

@MainActor
public struct DefaultSettingsLinkLabel: View {
    public init() {}

    public var body: some View {
        Text("Settings")
    }
}

@MainActor
public struct SettingsLink: View {
    public typealias Body = Never

    private let label: [AnyView]

    public init() {
        self.label = [AnyView(DefaultSettingsLinkLabel())]
    }

    public init(@ViewBuilder label: () -> [AnyView]) {
        self.label = label()
    }

    public var body: Never {
        fatalError("SettingsLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let openSettings = context.environmentValues.openSettings
        return Button {
            openSettings()
        } label: {
            label
        }
        .makeComponent(context: context)
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

    public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
        self.init(String(title), action: action)
    }

    public init(_ title: String, image name: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: name))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init<S: StringProtocol>(_ title: S, image name: String, action: @escaping @MainActor () -> Void) {
        self.init(String(title), image: name, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, image: name, action: action)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: resource))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, image: resource, action: action)
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

    public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(String(title), systemImage: systemImage, action: action)
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

    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(String(title), role: role, action: action)
    }

    public init(_ title: String, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: name))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init<S: StringProtocol>(_ title: S, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(String(title), image: name, role: role, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, image: name, role: role, action: action)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: resource))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, image: resource, role: role, action: action)
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

    public init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(String(title), systemImage: systemImage, role: role, action: action)
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
            let surfaceStyle = resolvedSurfaceStyle(for: buttonStyle, context: context)
            let buttonBorderShape = context.environmentValues.buttonBorderShape
            let node = Controls.button(
                runtime: runtime,
                layoutPriority: context.environmentValues.buttonSizing.retainedLayoutPriority,
                cornerRadius: buttonBorderShape.retainedCornerRadius(default: surfaceStyle.cornerRadius),
                palette: surfaceStyle.palette,
                chrome: surfaceStyle.chrome,
                clipsToBounds: surfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                repeatBehavior: context.environmentValues.buttonRepeatBehavior.retainedBehavior,
                animation: surfaceStyle.animation,
                action: {
                    ViewBuildContextScope.withCurrent(context) {
                        action()
                    }
                    context.invalidate()
                },
                children: [labelNode]
            )
            buttonBorderShape.applyRetainedDynamicCornerRadius(to: node)
            return node
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

    private func resolvedSurfaceStyle(for buttonStyle: ButtonStyle, context: ViewBuildContext) -> ButtonSurfaceStyle {
        if buttonStyle == .borderedProminent {
            return ButtonSurfaceStyle(
                cornerRadius: 16,
                palette: SurfacePalette(
                    idle: context.tint.opacity(0.84),
                    hovered: context.tint.opacity(0.92),
                    focused: context.tint.opacity(0.98),
                    pressed: context.tint,
                    activated: context.tint,
                    disabledBackground: Color(red: 0.20, green: 0.24, blue: 0.30, alpha: 0.50),
                    disabledForeground: Color(red: 0.66, green: 0.70, blue: 0.78, alpha: 0.72),
                    disabledBorder: Color(red: 0.50, green: 0.58, blue: 0.68, alpha: 0.20)
                ),
                chrome: SurfaceChrome(
                    borderColor: context.tint.opacity(0.34),
                    borderHoveredColor: context.tint.opacity(0.48),
                    borderFocusedColor: context.tint.opacity(0.60),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.38),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.34),
                    focusRingWidth: 2,
                    shadowColor: context.tint.opacity(0.20),
                    shadowHoveredColor: context.tint.opacity(0.26),
                    shadowFocusedColor: context.tint.opacity(0.32),
                    shadowPressedColor: context.tint.opacity(0.12),
                    shadowOffset: Point(x: 0, y: 14),
                    shadowSpread: 8
                ),
                clipsToBounds: true,
                animation: .default
            )
        }

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
public struct EditButton: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("EditButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let editMode = context.environmentValues.editMode
        let isEditing = editMode?.wrappedValue.isEditing == true
        return Button(isEditing ? "Done" : "Edit") {
            guard let editMode else {
                return
            }

            editMode.wrappedValue = isEditing ? .inactive : .active
        }
        .disabled(editMode == nil)
        .makeComponent(context: context)
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

private func resolvedSymbolIcon(for systemName: String, variants: SymbolVariants = .none) -> SymbolIcon {
    let resolvedName = variants.contains(.fill) && !systemName.hasSuffix(".fill")
        ? "\(systemName).fill"
        : systemName

    switch resolvedName {
    case "magnifyingglass":
        return .search
    case "folder":
        return .folder
    case "gear", "gear.fill", "gearshape", "gearshape.fill":
        return .settings
    case "bolt", "bolt.fill":
        return .lightning
    case "rectangle.3.group", "square.grid.3x1.folder.badge.plus":
        return .layout
    case "keyboard":
        return .keyboard
    case "sparkles":
        return .sparkle
    case "info", "info.fill", "info.circle", "info.circle.fill":
        return .info
    case "waveform.path.ecg", "waveform.path.ecg.fill", "chart.line.uptrend.xyaxis", "chart.line.uptrend.xyaxis.fill":
        return .activity
    case "doc", "doc.fill", "doc.text", "doc.text.fill":
        return .document
    case "rectangle.split.3x1", "rectangle.split.3x1.fill":
        return .split
    default:
        return .sparkle
    }
}

private struct ResolvedTextInputStyle {
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
    var padding: EdgeInsets
}

private extension TextFieldStyle {
    func resolvedTextInputStyle(isEnabled: Bool) -> ResolvedTextInputStyle {
        switch kind {
        case .automatic, .roundedBorder:
            return ResolvedTextInputStyle(
                backgroundColor: isEnabled
                    ? Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
                    : Color(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.58),
                borderColor: isEnabled
                    ? Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
                    : Color(red: 0.45, green: 0.48, blue: 0.52, alpha: 0.20),
                borderWidth: 1,
                cornerRadius: 8,
                padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            )
        case .squareBorder:
            return ResolvedTextInputStyle(
                backgroundColor: isEnabled
                    ? Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
                    : Color(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.58),
                borderColor: isEnabled
                    ? Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
                    : Color(red: 0.45, green: 0.48, blue: 0.52, alpha: 0.20),
                borderWidth: 1,
                cornerRadius: 0,
                padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            )
        case .plain:
            return ResolvedTextInputStyle(
                backgroundColor: .clear,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0,
                padding: EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0)
            )
        }
    }
}

private func textFieldInsertedCharacter(
    for event: KeyboardEvent,
    allowsNewlines: Bool,
    currentText: String,
    textInputAutocapitalization: TextInputAutocapitalization?
) -> String? {
    let insertedCharacter: String
    if event.key == .enter {
        guard allowsNewlines else {
            return nil
        }
        insertedCharacter = "\n"
        return insertedCharacter
    }

    if event.key == .space {
        insertedCharacter = " "
        return insertedCharacter
    }

    switch event.keyCode {
    case 0x30...0x39:
        insertedCharacter = String(UnicodeScalar(event.keyCode)!)
    case 0x41...0x5A:
        guard let scalar = UnicodeScalar(event.keyCode) else {
            return nil
        }

        let character = String(scalar)
        insertedCharacter = event.modifiers.contains(.shift) ? character : character.lowercased()
    case 0xBA:
        insertedCharacter = event.modifiers.contains(.shift) ? ":" : ";"
    case 0xBB:
        insertedCharacter = event.modifiers.contains(.shift) ? "+" : "="
    case 0xBC:
        insertedCharacter = event.modifiers.contains(.shift) ? "<" : ","
    case 0xBD:
        insertedCharacter = event.modifiers.contains(.shift) ? "_" : "-"
    case 0xBE:
        insertedCharacter = event.modifiers.contains(.shift) ? ">" : "."
    case 0xBF:
        insertedCharacter = event.modifiers.contains(.shift) ? "?" : "/"
    default:
        return nil
    }

    return autocapitalizedInsertedCharacter(
        insertedCharacter,
        currentText: currentText,
        textInputAutocapitalization: textInputAutocapitalization
    )
}

private func clampedTextOffset(_ offset: Int, in text: String) -> Int {
    min(max(0, offset), text.count)
}

private extension String {
    func textPrefix(upTo offset: Int) -> String {
        let clampedOffset = clampedTextOffset(offset, in: self)
        return String(prefix(clampedOffset))
    }

    func insertingText(_ insertedText: String, at offset: Int) -> String {
        let clampedOffset = clampedTextOffset(offset, in: self)
        let insertionIndex = index(startIndex, offsetBy: clampedOffset)
        var copy = self
        copy.insert(contentsOf: insertedText, at: insertionIndex)
        return copy
    }

    func removingText(in offsets: Range<Int>) -> String {
        let lowerBound = clampedTextOffset(offsets.lowerBound, in: self)
        let upperBound = clampedTextOffset(offsets.upperBound, in: self)
        guard lowerBound < upperBound else {
            return self
        }

        let lowerIndex = index(startIndex, offsetBy: lowerBound)
        let upperIndex = index(startIndex, offsetBy: upperBound)
        var copy = self
        copy.removeSubrange(lowerIndex..<upperIndex)
        return copy
    }
}

private func autocapitalizedInsertedCharacter(
    _ character: String,
    currentText: String,
    textInputAutocapitalization: TextInputAutocapitalization?
) -> String {
    switch textInputAutocapitalization {
    case .characters:
        return character.uppercased()
    case .words:
        return currentText.last.map { $0.isWhitespace || $0.isNewline } ?? true
            ? character.uppercased()
            : character
    case .sentences:
        guard shouldCapitalizeSentenceInsertion(after: currentText) else {
            return character
        }
        return character.uppercased()
    case .never, nil:
        return character
    }
}

private func shouldCapitalizeSentenceInsertion(after text: String) -> Bool {
    guard let lastCharacter = text.last else {
        return true
    }
    if lastCharacter.isNewline {
        return true
    }
    guard let lastMeaningfulCharacter = text.last(where: { !$0.isWhitespace && !$0.isNewline }) else {
        return true
    }
    return lastMeaningfulCharacter == "." || lastMeaningfulCharacter == "!" || lastMeaningfulCharacter == "?"
}
