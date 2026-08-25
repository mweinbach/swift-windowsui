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
    case backspace = 0x08
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
    case deleteForward = 0x2E
    case space = 0x20
    case mediaPlayPause = 0xB3
}
/// Where a scroll delta came from, which is the difference between a scroll
/// that should glide and one that should stop when it stops.
///
/// AppKit gives a momentum phase only to gesture devices — `NSEvent`'s
/// `momentumPhase` is populated for a trackpad or a Magic Mouse and never for
/// a click wheel. A discrete notch on macOS is a bounded jump. Windows makes
/// the same distinction available: a precision touchpad sends `WM_MOUSEWHEEL`
/// in fractions of `WHEEL_DELTA`, a click wheel in whole multiples of it.
public enum ScrollInputSource: Sendable, Equatable {
    /// One or more whole detents of a click wheel.
    case wheelNotch
    /// A continuous gesture: precision touchpad, Magic Mouse, or a synthetic
    /// high-resolution delta.
    case precise
}

/// How printable text associated with a key-down event reaches the focused
/// control.
///
/// Synthetic events retain their historical virtual-key inference so existing
/// embedders and tests do not change behavior. A real Win32 keyboard event is
/// followed by the layout-aware `WM_CHAR` stream instead; inferring a second
/// character from that event would insert every keystroke twice.
public enum KeyboardTextInputDelivery: Sendable, Equatable {
    case inferredFromVirtualKey
    case systemCharacter
}

public struct KeyboardEvent: Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyboardModifiers
    public var isRepeat: Bool
    public var textInputDelivery: KeyboardTextInputDelivery

    public init(
        keyCode: UInt32,
        modifiers: KeyboardModifiers = [],
        isRepeat: Bool = false,
        textInputDelivery: KeyboardTextInputDelivery = .inferredFromVirtualKey
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.textInputDelivery = textInputDelivery
    }

    public var key: KeyboardKey? {
        KeyboardKey(rawValue: keyCode)
    }
}
/// A focused text input's composition or Unicode commit event. Win32 IME
/// messages preserve their input-method source; translated keyboard
/// characters reuse the same selection-aware commit path with a keyboard
/// source so controls can distinguish ordinary typing from composed results.
public struct IMECompositionEvent: Sendable, Equatable {
    /// Regular keyboard characters share the focused text control's existing
    /// Unicode-aware commit path, but they still honor autocapitalization.
    /// Genuine IME results preserve their composed text exactly.
    public enum Source: Sendable, Equatable {
        case inputMethod
        case keyboard
    }

    public enum Phase: Sendable, Equatable {
        /// The IME started a composition session.
        case started
        /// The in-progress (marked) composition string changed. An empty
        /// string clears the marked text without committing.
        case updated(String)
        /// The IME produced a final result string to insert as normal text
        /// (replacing the current selection, if any).
        case committed(String)
        /// The composition session ended. Any marked text still showing is
        /// discarded when no commit preceded this.
        case ended
    }

    public var phase: Phase
    public var source: Source

    public init(phase: Phase, source: Source = .inputMethod) {
        self.phase = phase
        self.source = source
    }
}
