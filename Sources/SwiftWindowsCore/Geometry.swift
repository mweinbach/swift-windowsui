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

    public func applying(_ transform: Transform2D) -> Point {
        let matrix = transform.matrix
        return Point(
            x: matrix.a * x + matrix.c * y + matrix.tx,
            y: matrix.b * x + matrix.d * y + matrix.ty
        )
    }

    public func applying(transform: Transform2D, around center: Point) -> Point {
        let shifted = Point(x: x - center.x, y: y - center.y)
        let transformed = shifted.applying(transform)
        return Point(x: transformed.x + center.x, y: transformed.y + center.y)
    }

    public func distance(to other: Point) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }

    public func dot(_ other: Point) -> Double {
        x * other.x + y * other.y
    }

    public func cross(_ other: Point) -> Double {
        x * other.y - y * other.x
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

    public func scaled(by factor: Double, around center: Point) -> Rect {
        let newWidth = size.width * factor
        let newHeight = size.height * factor
        let newX = center.x + (origin.x - center.x) * factor
        let newY = center.y + (origin.y - center.y) * factor
        return Rect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    public func contains(point: Point, transform: Transform2D) -> Bool {
        let inverse = transform.inverse()
        let local = point.applying(inverse)
        return contains(local)
    }

    public func applying(transform: Transform2D) -> Rect {
        let p0 = Point(x: minX, y: minY).applying(transform)
        let p1 = Point(x: maxX, y: minY).applying(transform)
        let p2 = Point(x: minX, y: maxY).applying(transform)
        let p3 = Point(x: maxX, y: maxY).applying(transform)

        let newMinX = min(min(p0.x, p1.x), min(p2.x, p3.x))
        let newMinY = min(min(p0.y, p1.y), min(p2.y, p3.y))
        let newMaxX = max(max(p0.x, p1.x), max(p2.x, p3.x))
        let newMaxY = max(max(p0.y, p1.y), max(p2.y, p3.y))

        return Rect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
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

// MARK: - Affine Matrix

/// A 3x2 affine transformation matrix representing:
///   | a  b  0 |
///   | c  d  0 |
///   | tx ty 1 |
public struct AffineMatrix: Equatable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public func concatenating(_ other: AffineMatrix) -> AffineMatrix {
        AffineMatrix(
            a: a * other.a + b * other.c,
            b: a * other.b + b * other.d,
            c: c * other.a + d * other.c,
            d: c * other.b + d * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    public func inverted() -> AffineMatrix {
        let det = a * d - b * c
        guard det != 0 else { return self }
        let invDet = 1.0 / det
        return AffineMatrix(
            a: d * invDet,
            b: -b * invDet,
            c: -c * invDet,
            d: a * invDet,
            tx: (c * ty - d * tx) * invDet,
            ty: (b * tx - a * ty) * invDet
        )
    }
}

// MARK: - Transform2D

public struct Transform2D: Equatable, Sendable {
    public var translationX: Double
    public var translationY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotation: Double
    public var skewX: Double
    public var skewY: Double

    public init(
        translationX: Double = 0,
        translationY: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        rotation: Double = 0,
        skewX: Double = 0,
        skewY: Double = 0
    ) {
        self.translationX = translationX
        self.translationY = translationY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.skewX = skewX
        self.skewY = skewY
    }

    public static let identity = Transform2D()

    public var isIdentity: Bool {
        self == .identity
    }

    /// Creates a pure translation transform.
    public static func translation(x: Double, y: Double) -> Transform2D {
        Transform2D(translationX: x, translationY: y)
    }

    /// Creates a pure scale transform.
    public static func scale(x: Double, y: Double) -> Transform2D {
        Transform2D(scaleX: x, scaleY: y)
    }

    /// Applies this transform to a point.
    public func applying(to point: Point) -> Point {
        point.applying(self)
    }

    /// Returns the inverse, or nil if the matrix is singular.
    public func inverseOrNil() -> Transform2D? {
        let m = matrix
        let det = m.a * m.d - m.b * m.c
        guard abs(det) > 1e-12 else { return nil }
        return Transform2D(fromMatrix: m.inverted())
    }

    /// Builds the 3x2 affine matrix from decomposed components.
    /// Composition order: scale -> skew -> rotate -> translate.
    public var matrix: AffineMatrix {
        let cosR = _cos(rotation)
        let sinR = _sin(rotation)
        let tanSkewX = _tan(skewX)
        let tanSkewY = _tan(skewY)

        // Scale matrix: (scaleX, 0, 0, scaleY)
        // Skew matrix: (1, tanSkewY, tanSkewX, 1)
        // Combined scale+skew: (scaleX, scaleX*tanSkewY, scaleY*tanSkewX, scaleY)
        let sa = scaleX
        let sb = scaleX * tanSkewY
        let sc = scaleY * tanSkewX
        let sd = scaleY

        // Rotate the scale+skew result
        let a = sa * cosR + sb * (-sinR)
        let b = sa * sinR + sb * cosR
        let c = sc * cosR + sd * (-sinR)
        let d = sc * sinR + sd * cosR

        return AffineMatrix(
            a: a, b: b,
            c: c, d: d,
            tx: translationX,
            ty: translationY
        )
    }

    /// Composes two transforms using proper 3x2 affine matrix multiplication.
    public func concatenating(_ other: Transform2D) -> Transform2D {
        let result = matrix.concatenating(other.matrix)
        return Transform2D(fromMatrix: result)
    }

    /// Computes the inverse transform needed for hit testing rotated/scaled views.
    public func inverse() -> Transform2D {
        let inv = matrix.inverted()
        return Transform2D(fromMatrix: inv)
    }

    /// Decomposes an affine matrix back into translation, scale, rotation, and skew.
    public init(fromMatrix m: AffineMatrix) {
        translationX = m.tx
        translationY = m.ty

        // Decompose the 2x2 upper portion using QR-style decomposition.
        let sx = (m.a * m.a + m.b * m.b).squareRoot()
        guard sx != 0 else {
            scaleX = 0
            scaleY = 0
            rotation = 0
            skewX = 0
            skewY = 0
            return
        }

        rotation = _atan2(m.b, m.a)
        scaleX = sx

        let cosR = _cos(rotation)
        let sinR = _sin(rotation)

        // Remove rotation to recover skew+scale
        let r0 = m.a * cosR + m.b * sinR
        let r1 = m.c * cosR + m.d * sinR
        let r3 = m.c * (-sinR) + m.d * cosR

        // r0 = scaleX (already known as sx)
        // skewX = atan(r1 / r3) since r1 = scaleY * tan(skewX) and r3 = scaleY
        scaleY = (r1 * r1 + r3 * r3).squareRoot()

        if scaleY != 0 {
            skewX = _atan2(r1, r3)
        } else {
            skewX = 0
        }

        // Recover skewY from the upper-right element of the derotated matrix
        let ur = m.a * (-sinR) + m.b * cosR
        if r0 != 0 {
            skewY = _atan2(ur, r0)
        } else {
            skewY = 0
        }
    }

    /// Interpolates between two transforms, using shortest rotation path.
    public func interpolated(to other: Transform2D, progress: Double) -> Transform2D {
        let t = min(max(progress, 0), 1)

        // Normalize rotation difference to [-pi, pi] for shortest path
        var rotationDelta = other.rotation - rotation
        let pi = 3.14159265358979323846
        while rotationDelta > pi { rotationDelta -= 2 * pi }
        while rotationDelta < -pi { rotationDelta += 2 * pi }

        return Transform2D(
            translationX: translationX + (other.translationX - translationX) * t,
            translationY: translationY + (other.translationY - translationY) * t,
            scaleX: scaleX + (other.scaleX - scaleX) * t,
            scaleY: scaleY + (other.scaleY - scaleY) * t,
            rotation: rotation + rotationDelta * t,
            skewX: skewX + (other.skewX - skewX) * t,
            skewY: skewY + (other.skewY - skewY) * t
        )
    }
}

// MARK: - Math Helpers

// Wrappers to call C math functions available via the Swift runtime.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#elseif canImport(CRT)
import CRT
#endif

@usableFromInline
internal func _sin(_ x: Double) -> Double { sin(x) }

@usableFromInline
internal func _cos(_ x: Double) -> Double { cos(x) }

@usableFromInline
internal func _tan(_ x: Double) -> Double { tan(x) }

@usableFromInline
internal func _atan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }

@usableFromInline
internal func _acos(_ x: Double) -> Double { acos(x) }

// MARK: - Path

public enum PathElement: Equatable, Sendable {
    case moveTo(Point)
    case lineTo(Point)
    case quadraticCurveTo(control: Point, end: Point)
    case cubicCurveTo(control1: Point, control2: Point, end: Point)
    case arc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    case close
}

public struct Path: Equatable, Sendable {
    public private(set) var elements: [PathElement]

    public init() {
        elements = []
    }

    public init(elements: [PathElement]) {
        self.elements = elements
    }

    public var isEmpty: Bool { elements.isEmpty }

    // MARK: Builder Methods

    @discardableResult
    public mutating func moveTo(_ point: Point) -> Path {
        elements.append(.moveTo(point))
        return self
    }

    @discardableResult
    public mutating func moveTo(x: Double, y: Double) -> Path {
        moveTo(Point(x: x, y: y))
    }

    @discardableResult
    public mutating func lineTo(_ point: Point) -> Path {
        elements.append(.lineTo(point))
        return self
    }

    @discardableResult
    public mutating func lineTo(x: Double, y: Double) -> Path {
        lineTo(Point(x: x, y: y))
    }

    @discardableResult
    public mutating func close() -> Path {
        elements.append(.close)
        return self
    }

    @discardableResult
    public mutating func quadraticCurveTo(control: Point, end: Point) -> Path {
        elements.append(.quadraticCurveTo(control: control, end: end))
        return self
    }

    @discardableResult
    public mutating func cubicCurveTo(control1: Point, control2: Point, end: Point) -> Path {
        elements.append(.cubicCurveTo(control1: control1, control2: control2, end: end))
        return self
    }

    @discardableResult
    public mutating func arc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool = false) -> Path {
        elements.append(.arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise))
        return self
    }

    @discardableResult
    public mutating func addRect(_ rect: Rect) -> Path {
        moveTo(Point(x: rect.minX, y: rect.minY))
        lineTo(Point(x: rect.maxX, y: rect.minY))
        lineTo(Point(x: rect.maxX, y: rect.maxY))
        lineTo(Point(x: rect.minX, y: rect.maxY))
        return close()
    }

    @discardableResult
    public mutating func addEllipse(in rect: Rect) -> Path {
        let cx = rect.origin.x + rect.size.width / 2
        let cy = rect.origin.y + rect.size.height / 2
        let rx = rect.size.width / 2
        let ry = rect.size.height / 2

        // Approximate an ellipse using 4 cubic bezier curves
        // Magic number for control point distance: 4/3 * tan(pi/8) ~ 0.5522847498
        let k: Double = 0.5522847498

        moveTo(Point(x: cx + rx, y: cy))
        cubicCurveTo(
            control1: Point(x: cx + rx, y: cy + ry * k),
            control2: Point(x: cx + rx * k, y: cy + ry),
            end: Point(x: cx, y: cy + ry)
        )
        cubicCurveTo(
            control1: Point(x: cx - rx * k, y: cy + ry),
            control2: Point(x: cx - rx, y: cy + ry * k),
            end: Point(x: cx - rx, y: cy)
        )
        cubicCurveTo(
            control1: Point(x: cx - rx, y: cy - ry * k),
            control2: Point(x: cx - rx * k, y: cy - ry),
            end: Point(x: cx, y: cy - ry)
        )
        cubicCurveTo(
            control1: Point(x: cx + rx * k, y: cy - ry),
            control2: Point(x: cx + rx, y: cy - ry * k),
            end: Point(x: cx + rx, y: cy)
        )
        return close()
    }
}

// MARK: - Path Builder (Functional)

extension Path {
    public static func build(_ builder: (inout Path) -> Void) -> Path {
        var path = Path()
        builder(&path)
        return path
    }
}
