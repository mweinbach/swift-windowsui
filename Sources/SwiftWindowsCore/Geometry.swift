// MARK: - Affine Matrix

/// A 3x2 affine transformation matrix representing:
///   | a  b  0 |
///   | c  d  0 |
///   | tx ty 1 |

// MARK: - Transform2D

// MARK: - Math Helpers

// Wrappers to call C math functions available via the Swift runtime.
public struct IntSize: Equatable, Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32, height: Int32) {
        self.width = width
        self.height = height
    }

    public static let zero = IntSize(width: 0, height: 0)
}
public typealias CGSize = Size
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
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var width: Double { size.width }
    public var height: Double { size.height }
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
public enum Edge: Sendable, Equatable, Hashable {
    case top
    case leading
    case bottom
    case trailing

    public struct Set: OptionSet, Sendable, Equatable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
    }
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
    // System colors match Apple's documented macOS / SF Symbols values
    // (HIG → System colors). Pinned in docs/MacOSDesignParity.md so a
    // change here without a doc/test update fails CI.
    public static let red = Color(red: 1.0, green: 0.231, blue: 0.188, alpha: 1)
    public static let green = Color(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
    public static let blue = Color(red: 0.0, green: 0.478, blue: 1.0, alpha: 1)
    public static let orange = Color(red: 1.0, green: 0.584, blue: 0.0, alpha: 1)
    public static let yellow = Color(red: 1.0, green: 0.800, blue: 0.0, alpha: 1)
    public static let purple = Color(red: 0.686, green: 0.322, blue: 0.871, alpha: 1)
    public static let pink = Color(red: 1.0, green: 0.176, blue: 0.333, alpha: 1)
    public static let cyan = Color(red: 0.196, green: 0.678, blue: 0.902, alpha: 1)
    public static let brown = Color(red: 0.635, green: 0.518, blue: 0.369, alpha: 1)
    public static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839, alpha: 1)
    public static let mint = Color(red: 0.0, green: 0.780, blue: 0.745, alpha: 1)
    public static let teal = Color(red: 0.188, green: 0.690, blue: 0.780, alpha: 1)
    public static let gray = Color(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
    public static let primary = Color(red: 1, green: 1, blue: 1, alpha: 1)
    public static let secondary = Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 1)
    public static let highContrastSecondary = Color(red: 0.88, green: 0.92, blue: 0.98, alpha: 1)
    // macOS controlAccentColor default ("Multicolor → Blue") matches
    // Color.blue at #007AFF.
    // swift-format-ignore: DontRepeatTypeInStaticProperties
    public static let accentColor = Color(red: 0.0, green: 0.478, blue: 1.0, alpha: 1)

    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        var normalizedHue = hue.truncatingRemainder(dividingBy: 1)
        if normalizedHue < 0 { normalizedHue += 1 }
        let hueDegrees = normalizedHue * 360
        let c = brightness * saturation
        let x = c * (1 - abs((hueDegrees / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        var r: Double = 0
        var g: Double = 0
        var b: Double = 0
        switch hueDegrees {
        case 0..<60:
            r = c
            g = x
            b = 0
        case 60..<120:
            r = x
            g = c
            b = 0
        case 120..<180:
            r = 0
            g = c
            b = x
        case 180..<240:
            r = 0
            g = x
            b = c
        case 240..<300:
            r = x
            g = 0
            b = c
        default:
            r = c
            g = 0
            b = x
        }
        self.init(red: Float(r + m), green: Float(g + m), blue: Float(b + m), alpha: Float(opacity))
    }

    public func mix(with other: Color, by fraction: Double) -> Color {
        interpolated(to: other, progress: fraction)
    }

    public struct Resolved: Equatable, Sendable {
        public var red: Float
        public var green: Float
        public var blue: Float
        public var opacity: Float

        public init(red: Float, green: Float, blue: Float, opacity: Float) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }
    }

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

    public func multipliedAlpha(by multiplier: Float) -> Color {
        Color(
            red: red,
            green: green,
            blue: blue,
            alpha: max(0, min(1, alpha * multiplier))
        )
    }

    public init(_ colorSpace: String, colorComponents: [Float]) {
        let r = colorComponents.count > 0 ? colorComponents[0] : 0
        let g = colorComponents.count > 1 ? colorComponents[1] : 0
        let b = colorComponents.count > 2 ? colorComponents[2] : 0
        let a = colorComponents.count > 3 ? colorComponents[3] : 1
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    public init(cgColor: CGColor) {
        self.init(red: 0, green: 0, blue: 0, alpha: 1)
    }

    public init(_ resolved: Resolved) {
        self.init(red: resolved.red, green: resolved.green, blue: resolved.blue, alpha: resolved.opacity)
    }

    public init(uiColor: CGColor) {
        self.init(red: 0, green: 0, blue: 0, alpha: 1)
    }

    public init(nsColor: CGColor) {
        self.init(red: 0, green: 0, blue: 0, alpha: 1)
    }

    public var cgColor: CGColor {
        CGColor()
    }

    public var resolved: Resolved {
        Resolved(red: red, green: green, blue: blue, opacity: alpha)
    }
}
public struct CGColor: Sendable, Equatable {
    public init() {}
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
/// `atan(numerator / denominator)` without the division: the sign of the
/// denominator is normalised away first, so a negative scale reads back as a
/// skew in `(-pi/2, pi/2)` rather than the half turn `atan2` would report, and
/// a denominator near zero cannot blow the ratio up before the `atan`.
private func _skewAngle(_ numerator: Double, over denominator: Double) -> Double {
    denominator < 0 ? _atan2(-numerator, -denominator) : _atan2(numerator, denominator)
}
private func _snapDecomposedValue(_ value: Double) -> Double {
    let rounded = value.rounded()
    if abs(value - rounded) < 1e-12 {
        return rounded
    }
    if abs(value) < 1e-12 {
        return 0
    }
    return value
}
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

    /// Decomposes an affine matrix back into translation, scale, rotation, and
    /// skew — the inverse of `matrix`, and a round trip: `matrix` composes
    /// scale, then skew, then rotation, and this reads those same factors back
    /// out, so `Transform2D(fromMatrix: m).matrix` reproduces `m` for every
    /// non-singular `m`. That property is not decoration: `concatenating` and
    /// `inverse` both come back through here, so anything this cannot express
    /// is silently rewritten the first time a transform composes.
    ///
    /// **Reflections** are what it used to fail to express. A rotation
    /// preserves orientation, so a negative determinant can only be carried by
    /// a negative scale — and exactly two decompositions carry it, one with
    /// `scaleX < 0` and one with `scaleY < 0`, a half turn of rotation apart.
    /// Forcing non-negative scales chose neither, and the reflection came back
    /// as a half turn, so `.scaleEffect(x: -1)` placed its content upside down
    /// instead of mirrored. This takes whichever of the two branches is the
    /// smaller turn: a horizontal mirror decomposes to `scaleX: -1` with no
    /// rotation, a vertical one to `scaleY: -1` — the form the caller
    /// authored, and the one component-wise interpolation should walk.
    ///
    /// **Skew** was the same failure in a quieter place: `scaleY` was read as
    /// the norm of the second row, which is `scaleY / cos(skewX)`, so a shear
    /// grew by a factor of `sec(skewX)` every time it composed. Reading the
    /// derotated entries directly is exact for both.
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

        // `atan2(b, a)` is the turn that brings the first row back onto +x; the
        // half turn away from it brings it onto -x, which reads the reflection
        // as a negative `scaleX` instead of a negative `scaleY`. Both describe
        // the same matrix, so take the smaller turn.
        var angle = _atan2(m.b, m.a)
        let mirrorsX = (m.a * m.d - m.b * m.c) < 0 && abs(angle) > Double.pi / 2
        if mirrorsX {
            angle += angle > 0 ? -Double.pi : Double.pi
        }
        rotation = _snapDecomposedValue(angle)
        scaleX = _snapDecomposedValue(mirrorsX ? -sx : sx)

        let cosR = _cos(rotation)
        let sinR = _sin(rotation)

        // Removing the rotation leaves exactly the scale-and-skew matrix
        // `matrix` builds: (scaleX, scaleX·tanSkewY, scaleY·tanSkewX, scaleY).
        // The first entry is `scaleX` above (±sx by construction, kept in that
        // form so an unreflected decomposition is unchanged to the last bit).
        let upperRight = m.a * (-sinR) + m.b * cosR
        let lowerLeft = m.c * cosR + m.d * sinR
        let lowerRight = m.c * (-sinR) + m.d * cosR

        scaleY = _snapDecomposedValue(lowerRight)
        skewX = scaleY == 0 ? 0 : _snapDecomposedValue(_skewAngle(lowerLeft, over: lowerRight))
        skewY = _snapDecomposedValue(_skewAngle(upperRight, over: scaleX))
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

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(ucrt)
    import ucrt
#elseif canImport(CRT)
    import CRT
#endif

// MARK: - Path

// MARK: - Path Builder (Functional)

// MARK: - Angle

// MARK: - FillStyle

// MARK: - StrokeStyle

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
public enum PathElement: Equatable, Sendable {
    case moveTo(Point)
    case lineTo(Point)
    case quadraticCurveTo(control: Point, end: Point)
    case cubicCurveTo(control1: Point, control2: Point, end: Point)
    case arc(center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool)
    case close
}
public struct Path: Equatable, Sendable {
    public typealias Element = PathElement
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
    public mutating func arc(
        center: Point, radius: Double, startAngle: Double, endAngle: Double, clockwise: Bool = false
    ) -> Path {
        elements.append(
            .arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise))
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

    @discardableResult
    public mutating func addRoundedRect(_ rect: Rect, cornerRadius: Double) -> Path {
        let r = max(0, min(cornerRadius, min(rect.size.width, rect.size.height) / 2))
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        moveTo(Point(x: minX + r, y: minY))
        lineTo(Point(x: maxX - r, y: minY))
        arc(center: Point(x: maxX - r, y: minY + r), radius: r, startAngle: -Double.pi / 2, endAngle: 0)
        lineTo(Point(x: maxX, y: maxY - r))
        arc(center: Point(x: maxX - r, y: maxY - r), radius: r, startAngle: 0, endAngle: Double.pi / 2)
        lineTo(Point(x: minX + r, y: maxY))
        arc(center: Point(x: minX + r, y: maxY - r), radius: r, startAngle: Double.pi / 2, endAngle: Double.pi)
        lineTo(Point(x: minX, y: minY + r))
        arc(center: Point(x: minX + r, y: minY + r), radius: r, startAngle: Double.pi, endAngle: 3 * Double.pi / 2)
        return close()
    }

    // MARK: SwiftUI-named aliases

    public init(_ callback: (inout Path) -> Void) {
        self.init()
        callback(&self)
    }

    @discardableResult
    public mutating func move(to point: Point) -> Path {
        moveTo(point)
    }

    @discardableResult
    public mutating func addLine(to point: Point) -> Path {
        lineTo(point)
    }

    @discardableResult
    public mutating func addCurve(to end: Point, control1: Point, control2: Point) -> Path {
        cubicCurveTo(control1: control1, control2: control2, end: end)
    }

    @discardableResult
    public mutating func addQuadCurve(to end: Point, control: Point) -> Path {
        quadraticCurveTo(control: control, end: end)
    }

    @discardableResult
    public mutating func addLines(_ points: [Point]) -> Path {
        guard let first = points.first else { return self }
        if isEmpty {
            moveTo(first)
        } else {
            lineTo(first)
        }
        for point in points.dropFirst() {
            lineTo(point)
        }
        return self
    }

    @discardableResult
    public mutating func closeSubpath() -> Path {
        close()
    }

    public func trimmedPath(from: Double, to: Double) -> Path {
        self
    }

    public func strokedPath(_ style: StrokeStyle) -> Path {
        self
    }

    public func filledPath(_ style: FillStyle) -> Path {
        self
    }

    public init(_ cgPath: CGPath) {
        self.init()
    }

    public mutating func addRects(_ rects: [Rect]) {
        for rect in rects {
            addRect(rect)
        }
    }

    public mutating func addRelativeArc(center: Point, radius: Double, startAngle: Angle, delta: Angle) {
        arc(
            center: center, radius: radius, startAngle: startAngle.radians, endAngle: startAngle.radians + delta.radians
        )
    }

    public mutating func addArc(tangent1End: Point, tangent2End: Point, radius: Double) {
        lineTo(tangent1End)
        lineTo(tangent2End)
    }

    public func forEach(_ body: (PathElement) -> Void) {
        for element in elements {
            body(element)
        }
    }

    public var currentPoint: Point? {
        guard let last = elements.last else { return nil }
        switch last {
        case .moveTo(let p), .lineTo(let p), .quadraticCurveTo(_, let p), .cubicCurveTo(_, _, let p):
            return p
        case .arc(let center, let radius, _, let endAngle, _):
            return Point(x: center.x + radius * cos(endAngle), y: center.y + radius * sin(endAngle))
        case .close:
            return nil
        }
    }

    public var boundingRect: Rect {
        guard !elements.isEmpty else { return Rect(origin: .zero, size: .zero) }
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for element in elements {
            switch element {
            case .moveTo(let p), .lineTo(let p), .quadraticCurveTo(_, let p), .cubicCurveTo(_, _, let p):
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            case .arc(let center, let radius, _, _, _):
                minX = min(minX, center.x - radius)
                minY = min(minY, center.y - radius)
                maxX = max(maxX, center.x + radius)
                maxY = max(maxY, center.y + radius)
            case .close:
                break
            }
        }
        return Rect(origin: Point(x: minX, y: minY), size: CGSize(width: maxX - minX, height: maxY - minY))
    }

    /// Returns true when `point` lies inside the path's interior under the
    /// chosen fill rule.  Curves are flattened into short line segments before
    /// the ray-casting test runs, so the result is an approximation: accuracy
    /// improves with smaller curves and degrades for very long bezier
    /// segments.
    public func contains(_ point: Point, eoFill: Bool = false) -> Bool {
        let edges = flattenedEdges()
        guard !edges.isEmpty else { return false }
        if eoFill {
            return crossingsCount(at: point, edges: edges) % 2 == 1
        }
        return windingNumber(at: point, edges: edges) != 0
    }

    private struct Edge {
        let start: Point
        let end: Point
    }

    private func flattenedEdges(segmentsPerCurve: Int = 16) -> [Edge] {
        var edges: [Edge] = []
        var current = Point.zero
        var subpathStart = Point.zero
        var hasCurrent = false

        func addLine(to end: Point) {
            if hasCurrent {
                edges.append(Edge(start: current, end: end))
            }
            current = end
            hasCurrent = true
        }

        for element in elements {
            switch element {
            case .moveTo(let p):
                current = p
                subpathStart = p
                hasCurrent = true
            case .lineTo(let p):
                addLine(to: p)
            case .quadraticCurveTo(let c, let p):
                guard hasCurrent else {
                    current = p
                    hasCurrent = true
                    continue
                }
                var step = 1
                let start = current
                while step <= segmentsPerCurve {
                    let t = Double(step) / Double(segmentsPerCurve)
                    let oneMinusT = 1 - t
                    let x = oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * c.x + t * t * p.x
                    let y = oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * c.y + t * t * p.y
                    addLine(to: Point(x: x, y: y))
                    step += 1
                }
            case .cubicCurveTo(let c1, let c2, let p):
                guard hasCurrent else {
                    current = p
                    hasCurrent = true
                    continue
                }
                var step = 1
                let start = current
                while step <= segmentsPerCurve {
                    let t = Double(step) / Double(segmentsPerCurve)
                    let oneMinusT = 1 - t
                    let x =
                        oneMinusT * oneMinusT * oneMinusT * start.x
                        + 3 * oneMinusT * oneMinusT * t * c1.x
                        + 3 * oneMinusT * t * t * c2.x
                        + t * t * t * p.x
                    let y =
                        oneMinusT * oneMinusT * oneMinusT * start.y
                        + 3 * oneMinusT * oneMinusT * t * c1.y
                        + 3 * oneMinusT * t * t * c2.y
                        + t * t * t * p.y
                    addLine(to: Point(x: x, y: y))
                    step += 1
                }
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                let sweep: Double
                if clockwise {
                    sweep = endAngle >= startAngle ? endAngle - startAngle - 2 * .pi : endAngle - startAngle
                } else {
                    sweep = endAngle <= startAngle ? endAngle - startAngle + 2 * .pi : endAngle - startAngle
                }
                let steps = max(4, Int((abs(sweep) / (.pi / 8)).rounded(.up)))
                if !hasCurrent {
                    let startPoint = Point(
                        x: center.x + radius * cos(startAngle),
                        y: center.y + radius * sin(startAngle)
                    )
                    current = startPoint
                    subpathStart = startPoint
                    hasCurrent = true
                }
                var step = 1
                while step <= steps {
                    let t = Double(step) / Double(steps)
                    let angle = startAngle + sweep * t
                    let p = Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    addLine(to: p)
                    step += 1
                }
            case .close:
                if hasCurrent, current != subpathStart {
                    edges.append(Edge(start: current, end: subpathStart))
                    current = subpathStart
                }
            }
        }
        return edges
    }

    private func crossingsCount(at point: Point, edges: [Edge]) -> Int {
        var count = 0
        for edge in edges {
            let a = edge.start
            let b = edge.end
            let crossesY = (a.y > point.y) != (b.y > point.y)
            guard crossesY else { continue }
            let t = (point.y - a.y) / (b.y - a.y)
            let xIntersect = a.x + t * (b.x - a.x)
            if xIntersect > point.x {
                count += 1
            }
        }
        return count
    }

    private func windingNumber(at point: Point, edges: [Edge]) -> Int {
        var winding = 0
        for edge in edges {
            let a = edge.start
            let b = edge.end
            if a.y <= point.y {
                if b.y > point.y, edgeSide(a: a, b: b, point: point) > 0 {
                    winding += 1
                }
            } else {
                if b.y <= point.y, edgeSide(a: a, b: b, point: point) < 0 {
                    winding -= 1
                }
            }
        }
        return winding
    }

    private func edgeSide(a: Point, b: Point, point: Point) -> Double {
        (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
    }

    public func applying(_ transform: CGAffineTransform) -> Path {
        Path { path in
            for element in elements {
                switch element {
                case .moveTo(let p):
                    path.move(to: transform.apply(p))
                case .lineTo(let p):
                    path.addLine(to: transform.apply(p))
                case .quadraticCurveTo(let c, let p):
                    path.addQuadCurve(to: transform.apply(p), control: transform.apply(c))
                case .cubicCurveTo(let c1, let c2, let p):
                    path.addCurve(to: transform.apply(p), control1: transform.apply(c1), control2: transform.apply(c2))
                case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                    path.arc(
                        center: transform.apply(center), radius: radius, startAngle: startAngle, endAngle: endAngle,
                        clockwise: clockwise)
                case .close:
                    path.closeSubpath()
                }
            }
        }
    }

    public var cgPath: CGPath {
        CGPath()
    }
}
public struct CGAffineTransform: Sendable, Equatable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init() {
        self = .identity
    }

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public init(translationX tx: Double, y ty: Double) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    public init(scaleX sx: Double, y sy: Double) {
        self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    public init(rotationAngle angle: Double) {
        let cosine = cos(angle)
        let sine = sin(angle)
        self.init(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public func concatenating(_ other: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: a * other.a + b * other.c,
            b: a * other.b + b * other.d,
            c: c * other.a + d * other.c,
            d: c * other.b + d * other.d,
            tx: tx * other.a + ty * other.c + other.tx,
            ty: tx * other.b + ty * other.d + other.ty
        )
    }

    public func translatedBy(x: Double, y: Double) -> CGAffineTransform {
        concatenating(CGAffineTransform(translationX: x, y: y))
    }

    public func scaledBy(x sx: Double, y sy: Double) -> CGAffineTransform {
        concatenating(CGAffineTransform(scaleX: sx, y: sy))
    }

    public func rotated(by angle: Double) -> CGAffineTransform {
        concatenating(CGAffineTransform(rotationAngle: angle))
    }

    public func apply(_ point: Point) -> Point {
        Point(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
    }
}
extension Transform2D {
    public init(_ cgTransform: CGAffineTransform) {
        self.init(
            fromMatrix: AffineMatrix(
                a: cgTransform.a,
                b: cgTransform.b,
                c: cgTransform.c,
                d: cgTransform.d,
                tx: cgTransform.tx,
                ty: cgTransform.ty
            ))
    }

    public func concatenating(_ other: CGAffineTransform) -> Transform2D {
        concatenating(Transform2D(other))
    }
}
public struct CGPath: Sendable, Equatable {
    public init() {}
}
extension Path {
    public static func build(_ builder: (inout Path) -> Void) -> Path {
        var path = Path()
        builder(&path)
        return path
    }
}
public struct Angle: Sendable, Equatable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }

    public init(degrees: Double) {
        self.radians = degrees * .pi / 180
    }

    public var degrees: Double {
        radians * 180 / .pi
    }

    public static func radians(_ radians: Double) -> Angle {
        Angle(radians: radians)
    }

    public static func degrees(_ degrees: Double) -> Angle {
        Angle(degrees: degrees)
    }

    public static let zero = Angle(radians: 0)
}
public struct FillStyle: Sendable, Equatable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.isEOFilled = eoFill
        self.isAntialiased = antialiased
    }
}
public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: Double
    public var dashPattern: [Double]
    public var dashOffset: Double
    public var lineCap: LineCap
    public var lineJoin: LineJoin
    public var miterLimit: Double

    @_disfavoredOverload
    public init(
        lineWidth: Double = 1,
        dashPattern: [Double] = [],
        dashOffset: Double = 0,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10
    ) {
        self.lineWidth = lineWidth
        self.dashPattern = dashPattern
        self.dashOffset = dashOffset
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
    }

    public enum LineCap: Equatable, Sendable {
        case butt
        case round
        case square
    }

    public enum LineJoin: Equatable, Sendable {
        case miter
        case round
        case bevel
    }
}
public struct WindowTitleBarVisibility: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case visible
        case hidden
        case hiddenInFullScreen
        case automatic
    }

    public let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let visible = WindowTitleBarVisibility(kind: .visible)
    public static let hidden = WindowTitleBarVisibility(kind: .hidden)
    public static let hiddenInFullScreen = WindowTitleBarVisibility(kind: .hiddenInFullScreen)
    public static let automatic = WindowTitleBarVisibility(kind: .automatic)
}
