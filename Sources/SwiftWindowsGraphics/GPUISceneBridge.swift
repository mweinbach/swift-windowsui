import SwiftWindowsCore

// MARK: - Clip Stack Entry

/// Internal struct to track clip stack entries with their operation type.
/// Used by GPUISceneBridge to implement proper intersect/replace semantics.
private struct ClipStackEntry {
    var rect: Rect
    var operation: ClipOperation
}

// MARK: - RenderFrame to GPUIScene Bridge

extension GPUIScene {
    /// Creates a `GPUIScene` from an existing `RenderFrame`.
    ///
    /// The bridge walks each `RenderCommand` and converts it to the
    /// corresponding GPU primitive type. Paint order is preserved through
    /// per-layer paint operations instead of splitting layers every time the
    /// primitive family changes.
    ///
    /// ## Supported Mappings (VAL-SCENE-008)
    /// - Clear color: Preserved from frame to scene
    /// - `fillRect`: Maps to `quad` primitive with color/gradient
    /// - `drawBitmap`: Maps to `image` primitive
    /// - Default clip: Uses full surface size when no clip is active
    ///
    /// ## Clip Stack Semantics (VAL-SCENE-009)
    /// - `intersect`: Intersects with existing clip stack state (default behavior)
    /// - `replace`: Discards prior clip state and uses the new clip exclusively
    /// - `popClip` on empty stack: No-op (safe)
    /// - Empty resulting clip: Command is suppressed (omitted from scene)
    ///
    /// ## Soft-Failure Behavior (VAL-SCENE-010, VAL-SCENE-011)
    /// Unsupported commands are skipped safely without placeholder primitives:
    /// - `drawText`: Skipped (text rendered through separate scene path)
    /// - `fillPath`: Skipped (vector paths not yet supported)
    /// - `strokePath`: Skipped (vector paths not yet supported)
    /// - `applyBlur`: Skipped (blur effects not yet supported)
    ///
    /// Unsupported style features degrade to explicit fallbacks:
    /// - Ellipse clips: Fallback to bounding rect of the ellipse
    /// - Path clips: Fallback to full surface (no-op)
    /// - Radial/conic gradients: Fallback to base color (`cmd.color`)
    /// - Per-command blend modes: Ignored (uses default compositing; blend modes
    ///   like .multiply, .screen, .overlay, .additive fall back to normal blending)
    ///
    /// - Parameters:
    ///   - frame: The backend-neutral render frame to convert.
    ///   - surfaceSize: The surface dimensions, used as the default clip rect
    ///     when no explicit clip is active.
    public init(from frame: RenderFrame, surfaceSize: Size) {
        self = GPUIScene(clearColor: frame.clearColor)

        // Clip stack entries track both the clip rect and whether it was a "replace" operation
        // For replace operations, we don't intersect with parent clips
        var clipStack: [ClipStackEntry] = []

        for command in frame.commands {
            switch command {
            case .fillRect(let cmd):
                // Skip commands that result in an empty effective clip
                let effectiveClip = Self.resolveEffectiveClip(
                    commandClip: cmd.clipRect,
                    clipStack: clipStack,
                    surfaceSize: surfaceSize
                )
                guard !effectiveClip.isEmpty else {
                    // VAL-SCENE-009: Empty resulting clip suppresses command
                    continue
                }
                
                let quad = Self.makeQuad(
                    from: cmd,
                    effectiveClip: effectiveClip
                )
                self.addQuad(quad)

            case .drawBitmap(let cmd):
                // Skip commands that result in an empty effective clip
                let effectiveClip = Self.resolveEffectiveClip(
                    commandClip: cmd.clipRect,
                    clipStack: clipStack,
                    surfaceSize: surfaceSize
                )
                guard !effectiveClip.isEmpty else {
                    // VAL-SCENE-009: Empty resulting clip suppresses command
                    continue
                }
                
                let image = Self.makeImage(
                    from: cmd,
                    effectiveClip: effectiveClip
                )
                self.addImage(image)

            case .pushClip(let cmd):
                let clipRect: Rect
                switch cmd.shape {
                case .rect(let r, _):
                    clipRect = r
                case .ellipse(let center, let radiusX, let radiusY):
                    // VAL-SCENE-011: Non-rect clips fallback to bounding rect
                    clipRect = Rect(
                        x: center.x - radiusX,
                        y: center.y - radiusY,
                        width: radiusX * 2,
                        height: radiusY * 2
                    )
                case .path:
                    // VAL-SCENE-011: Path clips fallback to full surface (no-op)
                    clipRect = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
                }
                
                clipStack.append(ClipStackEntry(rect: clipRect, operation: cmd.operation))

            case .popClip:
                // VAL-SCENE-009: Empty-stack popClip is a safe no-op
                if !clipStack.isEmpty {
                    clipStack.removeLast()
                }

            case .drawText, .fillPath, .strokePath, .applyBlur:
                // VAL-SCENE-010: Unsupported commands are skipped safely
                // No placeholder primitives, no crashes, no reordering of neighbors
                break
            }
        }
    }

    // MARK: - Clip Resolution (VAL-SCENE-009)
    
    /// Resolves the effective clip rect from the stack and any per-command clip.
    /// 
    /// Clip semantics:
    /// - `intersect` operations intersect with the existing clip state
    /// - `replace` operations discard prior clip state for that level
    /// - Per-command clips intersect with the stack result
    /// - Empty stack uses full surface bounds
    private static func resolveEffectiveClip(
        commandClip: Rect?,
        clipStack: [ClipStackEntry],
        surfaceSize: Size
    ) -> Rect {
        let fullSurface = Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height)
        
        // Build effective clip from stack, respecting intersect vs replace operations
        var effective = fullSurface
        
        for entry in clipStack {
            switch entry.operation {
            case .intersect:
                if let intersected = effective.intersected(with: entry.rect) {
                    effective = intersected
                } else {
                    // No intersection - empty clip
                    return Rect.zero
                }
            case .replace:
                // Replace discards accumulated state and starts fresh
                effective = entry.rect
            }
        }
        
        // Apply per-command clip if present (always intersects)
        if let cmdClip = commandClip {
            if let intersected = effective.intersected(with: cmdClip) {
                effective = intersected
            } else {
                return Rect.zero
            }
        }
        
        return effective
    }

    // MARK: - Primitive Conversion Helpers

    /// Converts a `FillRectCommand` to a `QuadPrimitive`.
    /// 
    /// Gradient handling (VAL-SCENE-011):
    /// - Linear gradients: Mapped to quad gradient fields
    /// - Radial/conic gradients: Fallback to base color (`cmd.color`)
    private static func makeQuad(
        from cmd: FillRectCommand,
        effectiveClip: Rect
    ) -> QuadPrimitive {
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
                // VAL-SCENE-011: Radial/conic gradients fallback to base color (cmd.color)
                // (keep the base color values already set)
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
            clipX: Float(effectiveClip.origin.x),
            clipY: Float(effectiveClip.origin.y),
            clipWidth: Float(effectiveClip.size.width),
            clipHeight: Float(effectiveClip.size.height)
        )
    }

    /// Converts a `DrawBitmapCommand` to an `ImagePrimitive`.
    private static func makeImage(
        from cmd: DrawBitmapCommand,
        effectiveClip: Rect
    ) -> ImagePrimitive {
        return ImagePrimitive(
            screenX: Float(cmd.rect.origin.x),
            screenY: Float(cmd.rect.origin.y),
            screenW: Float(cmd.rect.size.width),
            screenH: Float(cmd.rect.size.height),
            uvX: 0, uvY: 0, uvW: 1, uvH: 1,
            opacity: cmd.opacity,
            clipX: Float(effectiveClip.origin.x),
            clipY: Float(effectiveClip.origin.y),
            clipWidth: Float(effectiveClip.size.width),
            clipHeight: Float(effectiveClip.size.height),
            textureID: -1
        )
    }
}
