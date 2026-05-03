import SwiftWindowsCore

// MARK: - RenderFrame to GPUIScene Bridge

public struct GPUISceneBridgeSkippedCommandCounts: Equatable, Sendable {
    public var fillPath: Int
    public var strokePath: Int
    public var drawText: Int
    public var applyBlur: Int

    public init(fillPath: Int = 0, strokePath: Int = 0, drawText: Int = 0, applyBlur: Int = 0) {
        self.fillPath = fillPath
        self.strokePath = strokePath
        self.drawText = drawText
        self.applyBlur = applyBlur
    }

    public var total: Int {
        fillPath + strokePath + drawText + applyBlur
    }

    public var isEmpty: Bool {
        total == 0
    }

    fileprivate mutating func record(_ command: RenderCommand) {
        switch command {
        case .fillPath:
            fillPath += 1
        case .strokePath:
            strokePath += 1
        case .drawText:
            drawText += 1
        case .applyBlur:
            applyBlur += 1
        case .fillRect, .shadowRect, .drawBitmap, .pushClip, .popClip:
            break
        }
    }
}

public struct GPUISceneBridgeResult: Equatable, Sendable {
    public var scene: GPUIScene
    public var skippedCommands: GPUISceneBridgeSkippedCommandCounts

    public init(scene: GPUIScene, skippedCommands: GPUISceneBridgeSkippedCommandCounts = GPUISceneBridgeSkippedCommandCounts()) {
        self.scene = scene
        self.skippedCommands = skippedCommands
    }
}

/// Tracks which primitive type was most recently appended so the bridge
/// can split layers on type transitions to preserve z-order.
private enum LastPrimitiveKind {
    case none
    case shadow
    case quad
    case image
}

extension GPUIScene {
    /// Creates a `GPUIScene` from an existing `RenderFrame`.
    ///
    /// The bridge walks each `RenderCommand` and converts it to the
    /// corresponding GPU primitive type. When consecutive commands produce
    /// different primitive types (e.g. `fillRect` followed by `drawBitmap`),
    /// a new layer is started to preserve z-ordering while still allowing
    /// batch rendering within each layer.
    ///
    /// - Parameters:
    ///   - frame: The backend-neutral render frame to convert.
    ///   - surfaceSize: The surface dimensions, used as the default clip rect
    ///     when no explicit clip is active.
    public init(from frame: RenderFrame, surfaceSize: Size) {
        self = Self.bridgeResult(from: frame, surfaceSize: surfaceSize).scene
    }

    /// Converts a `RenderFrame` while reporting command families that the
    /// current batch scene shape cannot represent yet.
    public static func bridgeResult(from frame: RenderFrame, surfaceSize: Size) -> GPUISceneBridgeResult {
        var scene = GPUIScene(clearColor: frame.clearColor)
        var skippedCommands = GPUISceneBridgeSkippedCommandCounts()

        var clipStack = RenderClipStack(surfaceSize: surfaceSize)
        var lastKind: LastPrimitiveKind = .none

        for command in frame.commands {
            switch command {
            case .shadowRect(let cmd):
                if lastKind != .none && lastKind != .shadow {
                    scene.pushLayer()
                }
                lastKind = .shadow
                let shadow = Self.makeShadow(from: cmd, clipStack: clipStack, surfaceSize: surfaceSize)
                scene.layers[scene.layers.count - 1].shadows.append(shadow)

            case .fillRect(let cmd):
                if lastKind != .none && lastKind != .quad {
                    scene.pushLayer()
                }
                lastKind = .quad
                let quad = Self.makeQuad(from: cmd, clipStack: clipStack, surfaceSize: surfaceSize)
                scene.layers[scene.layers.count - 1].quads.append(quad)

            case .drawBitmap(let cmd):
                if lastKind != .none && lastKind != .image {
                    scene.pushLayer()
                }
                lastKind = .image
                let textureID = scene.addImageResource(cmd.bitmap)
                let image = Self.makeImage(
                    from: cmd,
                    textureID: textureID,
                    clipStack: clipStack,
                    surfaceSize: surfaceSize
                )
                scene.layers[scene.layers.count - 1].images.append(image)

            case .pushClip(let cmd):
                clipStack.push(cmd)

            case .popClip:
                clipStack.pop()

            case .drawText, .fillPath, .strokePath, .applyBlur:
                // Not handled by the batch pipeline yet; skip.
                skippedCommands.record(command)
                break
            }
        }

        return GPUISceneBridgeResult(scene: scene, skippedCommands: skippedCommands)
    }

    // MARK: - Primitive Conversion Helpers

    /// Resolves the effective clip rect from the stack and any per-command clip.
    private static func resolveClip(
        commandClip: Rect?,
        clipStack: RenderClipStack,
        surfaceSize: Size
    ) -> Rect {
        let fullSurface = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        return clipStack.resolvedClip(commandClip: commandClip) ?? fullSurface
    }

    /// Converts a `FillRectCommand` to a `QuadPrimitive`.
    private static func makeQuad(
        from cmd: FillRectCommand,
        clipStack: RenderClipStack,
        surfaceSize: Size
    ) -> QuadPrimitive {
        let clip = resolveClip(commandClip: cmd.clipRect, clipStack: clipStack, surfaceSize: surfaceSize)

        var startR = cmd.color.red
        var startG = cmd.color.green
        var startB = cmd.color.blue
        var startA = cmd.color.alpha
        var endR = startR
        var endG = startG
        var endB = startB
        var endA = startA
        var axis: Float = 0

        if let gradient = cmd.gradient {
            switch gradient {
            case .linear(let lg):
                startR = lg.startColor.red
                startG = lg.startColor.green
                startB = lg.startColor.blue
                startA = lg.startColor.alpha
                endR = lg.endColor.red
                endG = lg.endColor.green
                endB = lg.endColor.blue
                endA = lg.endColor.alpha
                axis = lg.axis == .horizontal ? 1 : 0
            case .radial, .conic:
                // Fall back to solid color for unsupported gradient types.
                break
            }
        }

        return QuadPrimitive(
            x: Float(cmd.rect.origin.x),
            y: Float(cmd.rect.origin.y),
            width: Float(cmd.rect.size.width),
            height: Float(cmd.rect.size.height),
            cornerRadius: Float(cmd.cornerRadius),
            startR: startR, startG: startG, startB: startB, startA: startA,
            endR: endR, endG: endG, endB: endB, endA: endA,
            gradientAxis: axis,
            clipX: Float(clip.origin.x),
            clipY: Float(clip.origin.y),
            clipWidth: Float(clip.size.width),
            clipHeight: Float(clip.size.height)
        )
    }

    /// Converts a `ShadowRectCommand` to a `ShadowPrimitive`.
    private static func makeShadow(
        from cmd: ShadowRectCommand,
        clipStack: RenderClipStack,
        surfaceSize: Size
    ) -> ShadowPrimitive {
        let clip = resolveClip(commandClip: cmd.clipRect, clipStack: clipStack, surfaceSize: surfaceSize)

        return ShadowPrimitive(
            x: Float(cmd.rect.origin.x),
            y: Float(cmd.rect.origin.y),
            width: Float(cmd.rect.size.width),
            height: Float(cmd.rect.size.height),
            cornerRadius: Float(cmd.cornerRadius),
            colorR: cmd.color.red,
            colorG: cmd.color.green,
            colorB: cmd.color.blue,
            colorA: cmd.color.alpha,
            blurRadius: Float(max(0, cmd.blurRadius)),
            offsetX: Float(cmd.offset.x),
            offsetY: Float(cmd.offset.y),
            clipX: Float(clip.origin.x),
            clipY: Float(clip.origin.y),
            clipWidth: Float(clip.size.width),
            clipHeight: Float(clip.size.height)
        )
    }

    /// Converts a `DrawBitmapCommand` to an `ImagePrimitive`.
    private static func makeImage(
        from cmd: DrawBitmapCommand,
        textureID: Int32,
        clipStack: RenderClipStack,
        surfaceSize: Size
    ) -> ImagePrimitive {
        let clip = resolveClip(commandClip: cmd.clipRect, clipStack: clipStack, surfaceSize: surfaceSize)

        return ImagePrimitive(
            screenX: Float(cmd.rect.origin.x),
            screenY: Float(cmd.rect.origin.y),
            screenW: Float(cmd.rect.size.width),
            screenH: Float(cmd.rect.size.height),
            uvX: 0, uvY: 0, uvW: 1, uvH: 1,
            opacity: cmd.opacity,
            clipX: Float(clip.origin.x),
            clipY: Float(clip.origin.y),
            clipWidth: Float(clip.size.width),
            clipHeight: Float(clip.size.height),
            textureID: textureID
        )
    }
}
