import SwiftWindowsCore
import SwiftWindowsGraphics

/// Walks a ViewNode tree and produces a GPUIScene with typed primitive arrays,
/// mirroring the logic of ViewNode.appendCommands() but targeting the GPUI
/// instanced-rendering pipeline instead of the RenderCommand enum list.
@MainActor
public enum ScenePainter {

    public static func paint(root: ViewNode, clearColor: Color, surfaceSize: Size) -> GPUIScene {
        var scene = GPUIScene(clearColor: clearColor)
        let fullClip = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        paintNode(root, into: &scene, parentOrigin: .zero, inheritedClip: fullClip, surfaceSize: surfaceSize)
        return scene
    }

    // MARK: - Private

    private static func paintNode(
        _ node: ViewNode,
        into scene: inout GPUIScene,
        parentOrigin: Point,
        inheritedClip: Rect?,
        surfaceSize: Size
    ) {
        guard !node.isHidden else { return }

        let absoluteFrame = Rect(
            x: parentOrigin.x + node.resolvedFrame.origin.x,
            y: parentOrigin.y + node.resolvedFrame.origin.y,
            width: node.resolvedFrame.size.width,
            height: node.resolvedFrame.size.height
        )

        guard absoluteFrame.size.width > 0, absoluteFrame.size.height > 0 else { return }
        guard node.opacity > 0 else { return }

        // Occlusion culling against inherited clip.
        if !clipAllowsDrawing(clip: inheritedClip, rect: absoluteFrame) {
            return
        }

        var effectiveClip = inheritedClip
        if node.clipsToBounds {
            if let inherited = inheritedClip {
                guard let clipped = inherited.intersected(with: absoluteFrame) else {
                    return
                }
                effectiveClip = clipped
            } else {
                effectiveClip = absoluteFrame
            }
        }

        let layerIndex = scene.layers.count - 1
        let opacity = Float(node.opacity)

        // Shadow
        if node.shadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, node.shadowSpread))
                .offsetBy(dx: node.shadowOffset.x, dy: node.shadowOffset.y)

            if clipAllowsDrawing(clip: inheritedClip, rect: shadowRect) {
                scene.layers[layerIndex].shadows.append(ShadowPrimitive(
                    x: Float(shadowRect.origin.x),
                    y: Float(shadowRect.origin.y),
                    width: Float(shadowRect.size.width),
                    height: Float(shadowRect.size.height),
                    cornerRadius: Float(node.cornerRadius + max(0, node.shadowSpread)),
                    colorR: node.shadowColor.red,
                    colorG: node.shadowColor.green,
                    colorB: node.shadowColor.blue,
                    colorA: node.shadowColor.alpha,
                    blurRadius: Float(node.shadowSpread),
                    offsetX: Float(node.shadowOffset.x),
                    offsetY: Float(node.shadowOffset.y)
                ))
            }
        }

        // Outline (drawn outside the border)
        if node.outlineColor.alpha > 0, node.outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: node.outlineWidth)
            if clipAllowsDrawing(clip: inheritedClip, rect: outlineRect) {
                scene.layers[layerIndex].quads.append(solidQuad(
                    rect: outlineRect,
                    cornerRadius: node.cornerRadius + node.outlineWidth,
                    color: node.outlineColor,
                    opacity: opacity,
                    clip: inheritedClip,
                    surfaceSize: surfaceSize
                ))
            }
        }

        // Border (full rect drawn under the fill area)
        if node.borderColor.alpha > 0, node.borderWidth > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: absoluteFrame)
        {
            scene.layers[layerIndex].quads.append(solidQuad(
                rect: absoluteFrame,
                cornerRadius: node.cornerRadius,
                color: node.borderColor,
                opacity: opacity,
                clip: effectiveClip,
                surfaceSize: surfaceSize
            ))
        }

        // Background fill (inset by border width)
        let fillRect = node.borderWidth > 0 ? absoluteFrame.inset(by: node.borderWidth) : absoluteFrame
        let fillCornerRadius = max(0, node.cornerRadius - node.borderWidth)

        let resolvedBGColor = node.backgroundColor ?? node.backgroundGradient?.startColor
        if let bg = resolvedBGColor, bg.alpha > 0,
           fillRect.size.width > 0, fillRect.size.height > 0,
           clipAllowsDrawing(clip: effectiveClip, rect: fillRect)
        {
            let clipR = clipRectFloats(effectiveClip, surfaceSize: surfaceSize)
            let endColor = node.backgroundGradient?.endColor ?? bg
            let axis: Float = {
                guard let grad = node.backgroundGradient else { return 0 }
                return grad.axis == .horizontal ? 1 : 0
            }()

            scene.layers[layerIndex].quads.append(QuadPrimitive(
                x: Float(fillRect.origin.x),
                y: Float(fillRect.origin.y),
                width: Float(fillRect.size.width),
                height: Float(fillRect.size.height),
                cornerRadius: Float(fillCornerRadius),
                startR: bg.red, startG: bg.green, startB: bg.blue,
                startA: bg.alpha * opacity,
                endR: endColor.red, endG: endColor.green, endB: endColor.blue,
                endA: endColor.alpha * opacity,
                gradientAxis: axis,
                clipX: clipR.0, clipY: clipR.1,
                clipWidth: clipR.2, clipHeight: clipR.3
            ))
        }

        // Children -- sort by zIndex (stable), push new layers when zIndex changes.
        let childOrigin = Point(
            x: absoluteFrame.origin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
            y: absoluteFrame.origin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0)
        )

        let sortedChildren: [ViewNode]
        if node.children.contains(where: { $0.zIndex != 0 }) {
            sortedChildren = node.children.enumerated()
                .sorted { a, b in
                    if a.element.zIndex != b.element.zIndex {
                        return a.element.zIndex < b.element.zIndex
                    }
                    return a.offset < b.offset
                }
                .map(\.element)
        } else {
            sortedChildren = node.children
        }

        var currentZIndex = sortedChildren.first?.zIndex ?? 0
        for child in sortedChildren {
            if child.zIndex != currentZIndex {
                scene.pushLayer()
                currentZIndex = child.zIndex
            }
            paintNode(child, into: &scene, parentOrigin: childOrigin, inheritedClip: effectiveClip, surfaceSize: surfaceSize)
        }
    }

    // MARK: - Helpers

    /// Builds a solid-color QuadPrimitive (start color == end color, no gradient).
    private static func solidQuad(
        rect: Rect,
        cornerRadius: Double,
        color: Color,
        opacity: Float,
        clip: Rect?,
        surfaceSize: Size
    ) -> QuadPrimitive {
        let clipR = clipRectFloats(clip, surfaceSize: surfaceSize)
        let a = color.alpha * opacity
        return QuadPrimitive(
            x: Float(rect.origin.x),
            y: Float(rect.origin.y),
            width: Float(rect.size.width),
            height: Float(rect.size.height),
            cornerRadius: Float(cornerRadius),
            startR: color.red, startG: color.green, startB: color.blue, startA: a,
            endR: color.red, endG: color.green, endB: color.blue, endA: a,
            clipX: clipR.0, clipY: clipR.1,
            clipWidth: clipR.2, clipHeight: clipR.3
        )
    }

    private static func clipAllowsDrawing(clip: Rect?, rect: Rect) -> Bool {
        guard let clip = clip else { return true }
        return clip.intersected(with: rect) != nil
    }

    /// Converts an optional clip Rect into four Float values for primitive clip fields.
    private static func clipRectFloats(_ clip: Rect?, surfaceSize: Size) -> (Float, Float, Float, Float) {
        if let c = clip {
            return (Float(c.origin.x), Float(c.origin.y), Float(c.size.width), Float(c.size.height))
        }
        return (0, 0, Float(surfaceSize.width), Float(surfaceSize.height))
    }
}
