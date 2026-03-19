public enum MouseButton: UInt8, Sendable {
    case left
    case right
    case middle
}

public struct MouseEvent: Sendable {
    public var button: MouseButton
    public var position: Point
    public var clickCount: Int

    public init(button: MouseButton, position: Point, clickCount: Int = 1) {
        self.button = button
        self.position = position
        self.clickCount = clickCount
    }
}

public struct KeyboardModifiers: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyboardModifiers(rawValue: 1 << 0)
    public static let control = KeyboardModifiers(rawValue: 1 << 1)
    public static let alt = KeyboardModifiers(rawValue: 1 << 2)
}

public enum KeyboardKey: UInt32, Sendable {
    case tab = 0x09
    case enter = 0x0D
    case shift = 0x10
    case control = 0x11
    case alt = 0x12
    case escape = 0x1B
    case pageUp = 0x21
    case pageDown = 0x22
    case end = 0x23
    case home = 0x24
    case leftArrow = 0x25
    case upArrow = 0x26
    case rightArrow = 0x27
    case downArrow = 0x28
    case space = 0x20
}

public struct KeyboardEvent: Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyboardModifiers
    public var isRepeat: Bool

    public init(keyCode: UInt32, modifiers: KeyboardModifiers = [], isRepeat: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    public var key: KeyboardKey? {
        KeyboardKey(rawValue: keyCode)
    }
}
