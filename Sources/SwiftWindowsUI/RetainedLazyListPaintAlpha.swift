import SwiftWindowsCore
import SwiftWindowsGraphics

/// Provenance for inherited-opacity projection, before paint clamps alpha.
/// A recorded alpha of one cannot distinguish authored alpha one from two:
/// multiplying the recorded value later would not reproduce ordinary paint.
@MainActor
enum RetainedLazyListPaintAlpha {
    /// Inspects this node's stored paint values only. The caller separately
    /// checks original node opacity, every descendant and the Canvas witness.
    /// This never invokes a paint, layout, symbol or application callback.
    static func isUnit(in node: ViewNode) -> Bool {
        var scan = Scan()
        return scan.colors([
            node.backgroundColor, node.borderColor, node.outlineColor, node.shadowColor,
            node.scrollIndicatorColor, node.scrollIndicatorIdleColor,
            node.scrollIndicatorHoverColor, node.scrollIndicatorActiveColor,
            node.listRowPlatterColor, node.listRowSeparatorTint?.color,
            node.listSectionSeparatorTint?.color, node.listItemTint?.color,
        ])
            && scan.gradient(node.backgroundGradient)
            && scan.gradient(node.borderGradient)
            && scan.text(node.textStyle)
            && scan.effects(node.colorEffects)
    }

    /// The ordinary Canvas callback has already produced these operations.
    /// Inspect raw colors and draw opacity before inherited multiplication;
    /// lowering can hide an authored overrange value through saturation.
    static func isUnit(in operations: [CanvasGraphicsContext.Operation]) -> Bool {
        var scan = Scan()
        guard scan.consume(operations.count) else { return false }
        for operation in operations {
            switch operation {
            case .fillPath(_, let color), .fillPathWithRule(_, let color, _),
                .strokePath(_, let color, _), .fillRect(_, let color), .strokeRect(_, let color, _):
                guard isUnit(color) else { return false }
            case .fillPathGradient(_, let gradient, _, _), .fillPathGradientWithRule(_, let gradient, _, _, _),
                .strokePathGradient(_, let gradient, _, _, _), .fillRectGradient(_, let gradient):
                guard scan.stops(gradient.stops) else { return false }
            case .drawText(_, _, let style):
                guard scan.text(style) else { return false }
            case .drawImage(_, _, let opacity), .drawSymbol(_, _, _, let opacity):
                // Bitmap alpha is byte-valued. Symbols compose in their own
                // independent source; only this occurrence's scalar receives
                // the enclosing Canvas opacity. Do not enter their runtimes.
                guard isUnit(opacity) else { return false }
            case .pushClip, .popClip:
                break
            }
        }
        return true
    }

    private static func isUnit(_ color: Color) -> Bool { isUnit(color.alpha) }

    private static func isUnit(_ alpha: Float) -> Bool {
        alpha.isFinite && alpha >= 0 && alpha <= 1
    }

    @MainActor
    private struct Scan {
        private var remaining = RetainedLazyListPaintSource.maximumInspectedEntries

        mutating func consume(_ count: Int) -> Bool {
            guard count >= 0, count <= remaining else { return false }
            remaining -= count
            return true
        }

        mutating func colors(_ values: [Color?]) -> Bool {
            guard consume(values.count) else { return false }
            for value in values {
                if let value, !isUnit(value) { return false }
            }
            return true
        }

        mutating func gradient(_ value: GradientType?) -> Bool {
            switch value {
            case .linear(let gradient): return stops(gradient.stops)
            case .radial(let gradient): return stops(gradient.stops)
            case .conic(let gradient): return stops(gradient.stops)
            case nil: return true
            }
        }

        mutating func stops(_ values: [GradientStop]) -> Bool {
            guard consume(values.count) else { return false }
            for value in values where !isUnit(value.color) { return false }
            return true
        }

        mutating func text(_ initial: PixelTextStyle) -> Bool {
            guard consume(1) else { return false }
            var pending = [initial]
            while let style = pending.popLast() {
                guard isUnit(style.color) else { return false }
                if let color = style.underlineColor, !isUnit(color) { return false }
                if let color = style.strikethroughColor, !isUnit(color) { return false }
                if let spans = style.spans {
                    // Reserve before growing the work list. One budget covers
                    // all nested styles and all operations in this recording.
                    guard consume(spans.count) else { return false }
                    for span in spans { pending.append(span.style) }
                }
            }
            return true
        }

        mutating func effects(_ values: [RetainedColorEffect]) -> Bool {
            guard consume(values.count) else { return false }
            for value in values {
                switch value {
                case .colorMultiply(let color):
                    guard isUnit(color) else { return false }
                case .brightness, .contrast, .colorInvert, .saturation, .grayscale, .hueRotation, .luminanceToAlpha:
                    break
                }
            }
            return true
        }
    }
}
