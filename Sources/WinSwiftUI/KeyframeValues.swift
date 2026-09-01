import SwiftWindowsCore

extension Double: VectorArithmetic, Animatable {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { self }
        set { self = newValue }
    }

    public mutating func scale(by rhs: Double) {
        self *= rhs
    }

    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic, Animatable {
    public typealias AnimatableData = Float

    public var animatableData: Float {
        get { self }
        set { self = newValue }
    }

    public mutating func scale(by rhs: Double) {
        self = Float(Double(self) * rhs)
    }

    public var magnitudeSquared: Double { Double(self) * Double(self) }
}

extension SwiftWindowsCore.Point: Animatable {
    public typealias AnimatableData = AnimatablePair<Double, Double>

    public var animatableData: AnimatableData {
        get { AnimatablePair(x, y) }
        set {
            x = newValue.first
            y = newValue.second
        }
    }
}

extension SwiftWindowsCore.Size: Animatable {
    public typealias AnimatableData = AnimatablePair<Double, Double>

    public var animatableData: AnimatableData {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
        }
    }
}

extension SwiftWindowsCore.Rect: Animatable {
    public typealias AnimatableData = AnimatablePair<Point, Size>

    public var animatableData: AnimatableData {
        get { AnimatablePair(origin.animatableData, size.animatableData) }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second
        }
    }
}

extension SwiftWindowsCore.Angle: Animatable {
    public typealias AnimatableData = Double

    public var animatableData: Double {
        get { radians }
        set { radians = newValue }
    }
}
