import SwiftWindowsCore

// MARK: - RenderFrame to GPUIScene Bridge

extension GPUIScene {
    /// Creates a `GPUIScene` from an existing `RenderFrame`.
    ///
    /// The bridge walks each `RenderCommand` and converts it to the
    /// corresponding GPU primitive type. Paint order is preserved through
    /// per-layer paint operations instead of splitting layers every time the
    /// primitive family changes.
    ///
    /// - Parameters:
    ///   - frame: The backend-neutral render frame to convert.
    ///   - surfaceSize: The surface dimensions, used as the default clip rect
    ///     when no explicit clip is active.
    public init(from frame: RenderFrame, surfaceSize: Size) {
        self.clearColor = frame.clearColor
        self.layers = [GPUILayer()]

        var clipStack: [Rect] = []

        for command in frame.commands {
            switch command {
            case .fillRect(let cmd):
                let quad = Self.makeQuad(from: cmd, clipStack: clipStack, surfaceSize: surfaceSize)
                self.addQuad(quad)

            case .drawBitmap(let cmd):
                let image = Self.makeImage(from: cmd, clipStack: clipStack, surfaceSize: surfaceSize)
                self.addImage(image)

            case .pushClip(let cmd):
                switch cmd.shape {
                case .rect(let r, _):
                    clipStack.append(r)
                case .ellipse, .path:
                    // Non-rect clips are not supported in the batch pipeline yet.
                    // Push the bounding rect of the surface as a no-op clip.
                    clipStack.append(Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height))
                }

            case .popClip:
                if !clipStack.isEmpty {
                    clipStack.removeLast()
                }

            case .drawText, .fillPath, .strokePath, .applyBlur:
                // Not handled by the batch pipeline yet; skip.
                break
            }
        }
    }

    // MARK: - Primitive Conversion Helpers

    /// Resolves the effective clip rect from the stack and any per-command clip.
    private static func resolveClip(
        commandClip: Rect?,
        clipStack: [Rect],
        surfaceSize: Size
    ) -> Rect {
        let fullSurface = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        var effective = clipStack.last ?? fullSurface

        if let cmdClip = commandClip {
            effective = effective.intersected(with: cmdClip) ?? Rect.zero
        }

        return effective
    }

    /// Converts a `FillRectCommand` to a `QuadPrimitive`.
    private static func makeQuad(
        from cmd: FillRectCommand,
        clipStack: [Rect],
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

    /// Converts a `DrawBitmapCommand` to an `ImagePrimitive`.
    private static func makeImage(
        from cmd: DrawBitmapCommand,
        clipStack: [Rect],
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
            textureID: -1
        )
    }
}
