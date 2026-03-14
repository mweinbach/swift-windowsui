public struct IntSize: Equatable, Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    public static let zero = IntSize(width: 0, height: 0)
}

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func scaled(by factor: Double) -> Point {
        Point(x: x * factor, y: y * factor)
    }

    public static let zero = Point(x: 0, y: 0)
}

public struct Size: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public func scaled(by factor: Double) -> Size {
        Size(width: width * factor, height: height * factor)
    }

    public func divided(by factor: Double) -> Size {
        guard factor != 0 else {
            return self
        }

        return Size(width: width / factor, height: height / factor)
    }

    public static let zero = Size(width: 0, height: 0)
}

public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    public func intersected(with other: Rect) -> Rect? {
        let left = max(minX, other.minX)
        let top = max(minY, other.minY)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)

        guard right > left, bottom > top else {
            return nil
        }

        return Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func inset(by insets: EdgeInsets) -> Rect {
        let x = origin.x + insets.leading
        let y = origin.y + insets.top
        let width = max(0, size.width - insets.leading - insets.trailing)
        let height = max(0, size.height - insets.top - insets.bottom)
        return Rect(x: x, y: y, width: width, height: height)
    }

    public func inset(by amount: Double) -> Rect {
        inset(by: EdgeInsets(top: amount, leading: amount, bottom: amount, trailing: amount))
    }

    public func outset(by amount: Double) -> Rect {
        Rect(
            x: origin.x - amount,
            y: origin.y - amount,
            width: size.width + amount * 2,
            height: size.height + amount * 2
        )
    }

    public func offsetBy(dx: Double, dy: Double) -> Rect {
        Rect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
    }

    public func scaled(by factor: Double) -> Rect {
        Rect(origin: origin.scaled(by: factor), size: size.scaled(by: factor))
    }

    public static let zero = Rect(origin: .zero, size: .zero)
}

public struct EdgeInsets: Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

public struct Color: Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
    public static let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
    public static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)

    public var rgba: (Float, Float, Float, Float) {
        (red, green, blue, alpha)
    }

    public func interpolated(to other: Color, progress: Double) -> Color {
        let clampedProgress = Float(min(max(progress, 0), 1))
        return Color(
            red: red + (other.red - red) * clampedProgress,
            green: green + (other.green - green) * clampedProgress,
            blue: blue + (other.blue - blue) * clampedProgress,
            alpha: alpha + (other.alpha - alpha) * clampedProgress
        )
    }
}

public struct NativeWindowHandle: Equatable, Sendable {
    public let rawValue: UInt

    public init?(rawPointer: UnsafeMutableRawPointer?) {
        guard let rawPointer else {
            return nil
        }

        self.rawValue = UInt(bitPattern: rawPointer)
    }

    public var rawPointer: UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: rawValue)
    }
}

public struct SurfaceDescriptor: Equatable, Sendable {
    public var windowHandle: NativeWindowHandle
    public var pixelSize: IntSize
    public var scaleFactor: Double

    public init(windowHandle: NativeWindowHandle, pixelSize: IntSize, scaleFactor: Double) {
        self.windowHandle = windowHandle
        self.pixelSize = pixelSize
        self.scaleFactor = scaleFactor
    }
}
