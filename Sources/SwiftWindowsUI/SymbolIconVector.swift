import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

/// Draws `SymbolIcon` values as vector paths through the canvas/tessellator
/// pipeline. This is the last-resort icon renderer: it runs when no installed
/// icon font (Segoe Fluent Icons, Segoe MDL2 Assets) contains the symbol's
/// private-use codepoint, so an icon never degrades to a '?' glyph.
///
/// Shapes are authored on a 16x16 design grid and scaled to the paint size,
/// so they stay crisp at any display scale and pick up the tint color at
/// paint time.
@MainActor
enum SymbolIconVectorRenderer {
    static func draw(_ symbol: SymbolIcon, in size: Size, color: Color, into context: inout CanvasGraphicsContext) {
        guard size.width > 0, size.height > 0, color.alpha > 0 else {
            return
        }

        let grid: Double = 16
        let scale = min(size.width, size.height) / grid
        let offsetX = (size.width - grid * scale) * 0.5
        let offsetY = (size.height - grid * scale) * 0.5
        let stroke = StrokeStyle(lineWidth: max(1, 1.5 * scale), lineCap: .round, lineJoin: .round)

        func point(_ x: Double, _ y: Double) -> Point {
            Point(x: offsetX + x * scale, y: offsetY + y * scale)
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect {
            Rect(x: offsetX + x * scale, y: offsetY + y * scale, width: w * scale, height: h * scale)
        }
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            var path = Path()
            path.moveTo(point(x1, y1))
            path.lineTo(point(x2, y2))
            context.stroke(path, with: .color(color), style: stroke)
        }
        func polyline(_ points: [(Double, Double)]) {
            guard let first = points.first else { return }
            var path = Path()
            path.moveTo(point(first.0, first.1))
            for next in points.dropFirst() {
                path.lineTo(point(next.0, next.1))
            }
            context.stroke(path, with: .color(color), style: stroke)
        }
        func polygon(_ points: [(Double, Double)]) {
            guard let first = points.first else { return }
            var path = Path()
            path.moveTo(point(first.0, first.1))
            for next in points.dropFirst() {
                path.lineTo(point(next.0, next.1))
            }
            path.close()
            context.fill(path, with: .color(color))
        }
        func stroked(_ build: (inout Path) -> Void) {
            var path = Path()
            build(&path)
            context.stroke(path, with: .color(color), style: stroke)
        }
        func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            context.fill(rect(x, y, w, h), with: .color(color))
        }
        func fillCircle(_ cx: Double, _ cy: Double, _ r: Double) {
            var circle = Path()
            circle.addEllipse(in: rect(cx - r, cy - r, r * 2, r * 2))
            context.fill(circle, with: .color(color))
        }

        switch symbol {
        case .search:
            stroked { $0.addEllipse(in: rect(2.5, 2.5, 9, 9)) }
            line(10.4, 10.4, 13.8, 13.8)

        case .folder:
            stroked {
                $0.moveTo(point(2, 12.8))
                $0.lineTo(point(2, 3.6))
                $0.lineTo(point(6.2, 3.6))
                $0.lineTo(point(7.8, 5.6))
                $0.lineTo(point(14, 5.6))
                $0.lineTo(point(14, 12.8))
                $0.close()
            }

        case .settings:
            stroked { $0.addEllipse(in: rect(5.5, 5.5, 5, 5)) }
            for spoke in 0..<8 {
                let angle = Double(spoke) * .pi / 4
                line(
                    8 + 4.2 * cos(angle), 8 + 4.2 * sin(angle),
                    8 + 6.4 * cos(angle), 8 + 6.4 * sin(angle))
            }

        case .lightning:
            polygon([(9.2, 1.8), (4.2, 9), (7.4, 9), (6.4, 14.2), (11.8, 6.6), (8.4, 6.6)])

        case .layout:
            fillRect(2, 2, 5.4, 5.4)
            fillRect(8.6, 2, 5.4, 5.4)
            fillRect(2, 8.6, 5.4, 5.4)
            fillRect(8.6, 8.6, 5.4, 5.4)

        case .keyboard:
            stroked { $0.addRoundedRect(rect(1.4, 4.2, 13.2, 7.6), cornerRadius: 1.2 * scale) }
            fillRect(3, 6, 2, 1.6)
            fillRect(5.8, 6, 2, 1.6)
            fillRect(8.6, 6, 2, 1.6)
            fillRect(11.4, 6, 1.6, 1.6)
            fillRect(4.4, 8.8, 7.2, 1.4)

        case .sparkle:
            polygon([(8, 1.6), (9.9, 6.1), (14.4, 8), (9.9, 9.9), (8, 14.4), (6.1, 9.9), (1.6, 8), (6.1, 6.1)])

        case .info:
            stroked { $0.addEllipse(in: rect(2, 2, 12, 12)) }
            fillCircle(8, 5, 1)
            line(8, 7.4, 8, 11.6)

        case .activity:
            polyline([(1.4, 8), (4.6, 8), (6.2, 4.2), (9.2, 11.8), (10.8, 8), (14.6, 8)])

        case .document:
            stroked { $0.addRoundedRect(rect(3.8, 2, 8.4, 12), cornerRadius: 0.8 * scale) }
            line(5.8, 6, 10.2, 6)
            line(5.8, 8.6, 10.2, 8.6)
            line(5.8, 11.2, 8.6, 11.2)

        case .split:
            stroked { $0.addRoundedRect(rect(1.8, 3, 12.4, 10), cornerRadius: 0.8 * scale) }
            line(6.2, 3, 6.2, 13)
            line(10.2, 3, 10.2, 13)

        case .checkmark:
            polyline([(2.6, 8.6), (6.4, 12.2), (13.4, 3.8)])

        case .chevronDown:
            polyline([(3.4, 6), (8, 10.6), (12.6, 6)])

        case .chevronUp:
            polyline([(3.4, 10), (8, 5.4), (12.6, 10)])

        case .chevronLeft:
            polyline([(10, 3.4), (5.4, 8), (10, 12.6)])

        case .chevronRight:
            polyline([(6, 3.4), (10.6, 8), (6, 12.6)])

        case .radioSelected:
            stroked { $0.addEllipse(in: rect(2, 2, 12, 12)) }
            fillCircle(8, 8, 3)

        case .radioUnselected:
            stroked { $0.addEllipse(in: rect(2, 2, 12, 12)) }

        case .plus:
            line(8, 2.8, 8, 13.2)
            line(2.8, 8, 13.2, 8)

        case .minus:
            line(2.8, 8, 13.2, 8)

        case .xmark:
            line(3.6, 3.6, 12.4, 12.4)
            line(12.4, 3.6, 3.6, 12.4)

        case .play:
            polygon([(4.8, 3), (13, 8), (4.8, 13)])

        case .pause:
            fillRect(4, 3, 2.8, 10)
            fillRect(9.2, 3, 2.8, 10)

        case .arrowLeft:
            line(13.2, 8, 2.8, 8)
            polyline([(6.6, 4.2), (2.8, 8), (6.6, 11.8)])

        case .arrowRight:
            line(2.8, 8, 13.2, 8)
            polyline([(9.4, 4.2), (13.2, 8), (9.4, 11.8)])

        case .arrowUp:
            line(8, 13.2, 8, 2.8)
            polyline([(4.2, 6.6), (8, 2.8), (11.8, 6.6)])

        case .arrowDown:
            line(8, 2.8, 8, 13.2)
            polyline([(4.2, 9.4), (8, 13.2), (11.8, 9.4)])

        case .ellipsis:
            fillCircle(3.2, 8, 1.3)
            fillCircle(8, 8, 1.3)
            fillCircle(12.8, 8, 1.3)

        case .trash:
            stroked {
                $0.moveTo(point(4.4, 4.6))
                $0.lineTo(point(11.6, 4.6))
                $0.lineTo(point(10.8, 13.4))
                $0.lineTo(point(5.2, 13.4))
                $0.close()
            }
            line(2.8, 4.6, 13.2, 4.6)
            line(6.4, 2.6, 9.6, 2.6)

        case .pencil:
            stroked {
                $0.moveTo(point(2.8, 10.6))
                $0.lineTo(point(10.6, 2.8))
                $0.lineTo(point(13.2, 5.4))
                $0.lineTo(point(5.4, 13.2))
                $0.lineTo(point(2.8, 13.2))
                $0.close()
            }

        case .person:
            stroked { $0.addEllipse(in: rect(5.4, 2.2, 5.2, 5.2)) }
            stroked {
                $0.moveTo(point(2.6, 13.8))
                $0.cubicCurveTo(control1: point(3.2, 9.6), control2: point(12.8, 9.6), end: point(13.4, 13.8))
            }

        case .house:
            stroked {
                $0.moveTo(point(3.4, 13.4))
                $0.lineTo(point(3.4, 8))
                $0.lineTo(point(8, 3.2))
                $0.lineTo(point(12.6, 8))
                $0.lineTo(point(12.6, 13.4))
                $0.close()
            }

        case .star, .starFill:
            var vertices = Path()
            for index in 0..<10 {
                let radius = index % 2 == 0 ? 6.2 : 2.5
                let angle = -Double.pi / 2 + Double(index) * .pi / 5
                let vertex = point(8 + radius * cos(angle), 8 + radius * sin(angle))
                if index == 0 {
                    vertices.moveTo(vertex)
                } else {
                    vertices.lineTo(vertex)
                }
            }
            vertices.close()
            if symbol == .starFill {
                context.fill(vertices, with: .color(color))
            } else {
                context.stroke(vertices, with: .color(color), style: stroke)
            }

        case .heart, .heartFill:
            var outline = Path()
            outline.moveTo(point(8, 13.6))
            outline.cubicCurveTo(control1: point(2.2, 9), control2: point(3.4, 3.2), end: point(8, 6.2))
            outline.cubicCurveTo(control1: point(12.6, 3.2), control2: point(13.8, 9), end: point(8, 13.6))
            outline.close()
            if symbol == .heartFill {
                context.fill(outline, with: .color(color))
            } else {
                context.stroke(outline, with: .color(color), style: stroke)
            }

        case .bell:
            stroked {
                $0.moveTo(point(4.4, 11.4))
                $0.cubicCurveTo(control1: point(4.4, 4.2), control2: point(11.6, 4.2), end: point(11.6, 11.4))
            }
            line(3, 11.4, 13, 11.4)
            fillCircle(8, 13.4, 1.1)

        case .camera:
            stroked { $0.addRoundedRect(rect(1.8, 4.6, 12.4, 8.2), cornerRadius: 1 * scale) }
            polyline([(5.4, 4.6), (6.4, 2.8), (9.6, 2.8), (10.6, 4.6)])
            stroked { $0.addEllipse(in: rect(5.7, 6.2, 4.6, 4.6)) }

        case .globe:
            stroked { $0.addEllipse(in: rect(2, 2, 12, 12)) }
            stroked { $0.addEllipse(in: rect(5.4, 2, 5.2, 12)) }
            line(2, 8, 14, 8)

        case .mapPin:
            stroked {
                $0.moveTo(point(8, 14.2))
                $0.cubicCurveTo(control1: point(3.4, 8.6), control2: point(3.6, 2.4), end: point(8, 2.4))
                $0.cubicCurveTo(control1: point(12.4, 2.4), control2: point(12.6, 8.6), end: point(8, 14.2))
            }
            fillCircle(8, 6.4, 1.4)
        }
    }
}
