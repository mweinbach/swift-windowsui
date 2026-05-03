import SwiftWindowsCore

/// Resolves the effective rectangular clip for renderers that currently expose
/// only scissor-style clipping.
public struct RenderClipStack: Equatable, Sendable {
    public let surfaceRect: Rect
    private var stack: [Rect] = []

    public init(surfaceSize: Size) {
        self.init(surfaceRect: Rect(x: 0, y: 0, width: surfaceSize.width, height: surfaceSize.height))
    }

    public init(surfaceRect: Rect) {
        self.surfaceRect = surfaceRect
    }

    public var currentClip: Rect? {
        stack.last
    }

    public mutating func push(_ command: ClipCommand) {
        let shapeBounds = rectangularBounds(for: command.shape) ?? Rect.zero
        let nextClip: Rect?

        switch command.operation {
        case .intersect:
            let base = currentClip ?? surfaceRect
            nextClip = base.intersected(with: shapeBounds)
        case .replace:
            nextClip = surfaceRect.intersected(with: shapeBounds)
        }

        stack.append(nextClip ?? Rect.zero)
    }

    public mutating func pop() {
        guard !stack.isEmpty else {
            return
        }

        stack.removeLast()
    }

    public func resolvedClip(commandClip: Rect?) -> Rect? {
        switch (currentClip, commandClip) {
        case (.none, .none):
            return nil
        case (.some(let clip), .none):
            return clip
        case (.none, .some(let clip)):
            return clip
        case (.some(let activeClip), .some(let commandClip)):
            return activeClip.intersected(with: commandClip) ?? Rect.zero
        }
    }
}

private func rectangularBounds(for shape: ClipShape) -> Rect? {
    switch shape {
    case .rect(let rect, _):
        return rect
    case .ellipse(let center, let radiusX, let radiusY):
        return Rect(
            x: center.x - radiusX,
            y: center.y - radiusY,
            width: radiusX * 2,
            height: radiusY * 2
        )
    case .path(let path):
        return pathBounds(path)
    }
}

private func pathBounds(_ path: RenderPath) -> Rect? {
    var minX = Double.infinity
    var minY = Double.infinity
    var maxX = -Double.infinity
    var maxY = -Double.infinity

    func include(_ point: Point) {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }

    for segment in path.segments {
        switch segment {
        case .moveTo(let point), .lineTo(let point):
            include(point)
        case .quadCurveTo(let control, let end):
            include(control)
            include(end)
        case .cubicCurveTo(let control1, let control2, let end):
            include(control1)
            include(control2)
            include(end)
        case .close:
            break
        }
    }

    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
        return nil
    }

    return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
