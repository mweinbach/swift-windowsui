import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@Suite("RenderClipStack Tests")
struct RenderClipStackTests {
    private let surfaceSize = Size(width: 500, height: 400)

    @Test("No active clip preserves command clip")
    func noActiveClipPreservesCommandClip() {
        let commandClip = Rect(x: 20, y: 30, width: 80, height: 90)
        let stack = RenderClipStack(surfaceSize: surfaceSize)

        #expect(stack.currentClip == nil)
        #expect(stack.resolvedClip(commandClip: nil) == nil)
        #expect(stack.resolvedClip(commandClip: commandClip) == commandClip)
    }

    @Test("Nested intersect clips resolve to the visible intersection")
    func nestedIntersectClipsResolveToIntersection() {
        var stack = RenderClipStack(surfaceSize: surfaceSize)

        stack.push(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 300, height: 300), cornerRadius: 0)))
        stack.push(ClipCommand(shape: .rect(Rect(x: 100, y: 120, width: 300, height: 200), cornerRadius: 0)))

        #expect(stack.currentClip == Rect(x: 100, y: 120, width: 200, height: 180))
        #expect(stack.resolvedClip(commandClip: Rect(x: 140, y: 140, width: 100, height: 220)) == Rect(x: 140, y: 140, width: 100, height: 160))
    }

    @Test("Pop restores previous clip")
    func popRestoresPreviousClip() {
        let outer = Rect(x: 10, y: 20, width: 300, height: 300)
        let inner = Rect(x: 100, y: 120, width: 60, height: 70)
        var stack = RenderClipStack(surfaceSize: surfaceSize)

        stack.push(ClipCommand(shape: .rect(outer, cornerRadius: 0)))
        stack.push(ClipCommand(shape: .rect(inner, cornerRadius: 0)))
        stack.pop()

        #expect(stack.currentClip == outer)
    }

    @Test("Replace clip ignores previous active clip")
    func replaceClipIgnoresPreviousActiveClip() {
        var stack = RenderClipStack(surfaceSize: surfaceSize)

        stack.push(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 0)))
        stack.push(ClipCommand(
            shape: .rect(Rect(x: 250, y: 260, width: 80, height: 90), cornerRadius: 0),
            operation: .replace
        ))

        #expect(stack.currentClip == Rect(x: 250, y: 260, width: 80, height: 90))
    }

    @Test("Ellipse and path clips use rectangular bounds")
    func nonRectangularClipsUseBounds() {
        var path = RenderPath()
        path.move(to: Point(x: 40, y: 50))
        path.addLine(to: Point(x: 180, y: 60))
        path.addQuadCurve(to: Point(x: 140, y: 220), control: Point(x: 240, y: 120))

        var ellipseStack = RenderClipStack(surfaceSize: surfaceSize)
        ellipseStack.push(ClipCommand(shape: .ellipse(center: Point(x: 100, y: 90), radiusX: 30, radiusY: 40)))

        var pathStack = RenderClipStack(surfaceSize: surfaceSize)
        pathStack.push(ClipCommand(shape: .path(path)))

        #expect(ellipseStack.currentClip == Rect(x: 70, y: 50, width: 60, height: 80))
        #expect(pathStack.currentClip == Rect(x: 40, y: 50, width: 200, height: 170))
    }
}
