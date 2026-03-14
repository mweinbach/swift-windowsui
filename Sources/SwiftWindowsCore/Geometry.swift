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

    public static let zero = Point(x: 0, y: 0)
}

public struct Size: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
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
