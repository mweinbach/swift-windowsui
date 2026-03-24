import SwiftWindowsCore

// MARK: - GPUIScene Bridge
//
// Converts the existing RenderFrame command list into a GPUIScene. This bridge
// enables the batch renderer to work with the current runtime pipeline without
// requiring all views to be rewritten.

extension GPUIScene {
    /// Categorises the primitive type that a RenderCommand maps to.
    private enum PrimitiveType {
        case quad
        case image
        case glyph
        case shadow
    }

    /// Create a GPUIScene from an existing RenderFrame.
    ///
    /// Commands are walked in order. Consecutive commands of the same primitive
    /// type are batched into the current layer. When the primitive type changes,
    /// a new layer is pushed so that draw-order is preserved.
    public init(from frame: RenderFrame, surfaceSize: Size) {
        self.clearColor = frame.clearColor
        self.layers = [GPUILayer()]

        var clipStack: [Rect] = [
            Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        ]
        var lastPrimitiveType: PrimitiveType? = nil

        for command in frame.commands {
            switch command {
            case .fillRect(let cmd):
                if lastPrimitiveType != nil && lastPrimitiveType != .quad {
                    self.pushLayer()
                }
                let currentClip = clipStack.last
                let quad = QuadPrimitive(
                    x: Float(cmd.rect.origin.x),
                    y: Float(cmd.rect.origin.y),
                    width: Float(cmd.rect.size.width),
                    height: Float(cmd.rect.size.height),
                    cornerRadius: Float(cmd.cornerRadius),
                    red: Float(cmd.color.red),
                    green: Float(cmd.color.green),
                    blue: Float(cmd.color.blue),
                    alpha: Float(cmd.color.alpha),
                    clipRect: currentClip.map {
                        (Float($0.origin.x), Float($0.origin.y),
                         Float($0.size.width), Float($0.size.height))
                    }
                )
                layers[layers.count - 1].quads.append(quad)
                lastPrimitiveType = .quad

            case .drawBitmap(let cmd):
                if lastPrimitiveType != nil && lastPrimitiveType != .image {
                    self.pushLayer()
                }
                let image = ImagePrimitive(
                    x: Float(cmd.rect.origin.x),
                    y: Float(cmd.rect.origin.y),
                    width: Float(cmd.rect.size.width),
                    height: Float(cmd.rect.size.height),
                    opacity: cmd.opacity,
                    textureID: 0
                )
                layers[layers.count - 1].images.append(image)
                lastPrimitiveType = .image

            case .drawText(let cmd):
                if lastPrimitiveType != nil && lastPrimitiveType != .glyph {
                    self.pushLayer()
                }
                // Text is represented as a single glyph primitive placeholder.
                // The real glyph atlas integration will decompose this into
                // per-character GlyphPrimitives when Unit 5 is merged.
                let glyph = GlyphPrimitive(
                    x: Float(cmd.position.x),
                    y: Float(cmd.position.y),
                    width: Float(cmd.fontSize),
                    height: Float(cmd.fontSize),
                    red: Float(cmd.color.red),
                    green: Float(cmd.color.green),
                    blue: Float(cmd.color.blue),
                    alpha: Float(cmd.color.alpha)
                )
                layers[layers.count - 1].glyphs.append(glyph)
                lastPrimitiveType = .glyph

            case .pushClip(let cmd):
                if case .rect(let r, _) = cmd.shape {
                    clipStack.append(r)
                }

            case .popClip:
                if clipStack.count > 1 {
                    clipStack.removeLast()
                }

            default:
                // fillPath, strokePath, applyBlur — not yet mapped to GPUI
                // primitives. These will be handled when the full batch
                // renderer (Unit 7) is merged.
                break
            }
        }
    }
}
