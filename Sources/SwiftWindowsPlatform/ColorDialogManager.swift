import Foundation
import SwiftWindowsCore
import WinSDK

/// Abstraction over the native Win32 color picker. The production default is
/// `Win32ColorDialogProvider`, which shows the modal `ChooseColorW` common
/// dialog; tests inject a fake so no live dialog appears on headless runners
/// (same pattern as `FileDialogProvider`).
@MainActor
public protocol ColorDialogProvider: AnyObject {
    /// Shows the color dialog seeded with `initial`. Returns the chosen color,
    /// or `nil` when the user cancels. The returned color keeps the initial
    /// alpha — the Win32 common dialog has no opacity channel.
    func chooseColor(initial: Color) -> Color?
}

/// Live Win32 `ChooseColorW` common-dialog provider.
public final class Win32ColorDialogProvider: ColorDialogProvider {
    /// `CC_RGBINIT | CC_FULLOPEN` from commdlg.h; not exposed by the WinSDK
    /// Swift module.
    private static let rgbInitAndFullOpen = DWORD(0x0000_0001 | 0x0000_0002)

    public init() {}

    public func chooseColor(initial: Color) -> Color? {
        var customColors = [DWORD](repeating: 0x00FF_FFFF, count: 16)
        var chooser = CHOOSECOLORW()
        chooser.lStructSize = DWORD(MemoryLayout<CHOOSECOLORW>.size)
        chooser.hwndOwner = GetActiveWindow()
        chooser.rgbResult = Self.colorRef(for: initial)
        chooser.Flags = Self.rgbInitAndFullOpen

        return customColors.withUnsafeMutableBufferPointer { buffer in
            chooser.lpCustColors = buffer.baseAddress
            guard ChooseColorW(&chooser) else {
                return nil
            }
            return Self.color(from: chooser.rgbResult, alpha: initial.alpha)
        }
    }

    /// COLORREF layout is 0x00BBGGRR.
    private static func colorRef(for color: Color) -> DWORD {
        let red = DWORD(clampingChannel(color.red))
        let green = DWORD(clampingChannel(color.green))
        let blue = DWORD(clampingChannel(color.blue))
        return red | (green << 8) | (blue << 16)
    }

    private static func color(from colorRef: DWORD, alpha: Float) -> Color {
        Color(
            red: Float(colorRef & 0xFF) / 255.0,
            green: Float((colorRef >> 8) & 0xFF) / 255.0,
            blue: Float((colorRef >> 16) & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    private static func clampingChannel(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}

@MainActor
public enum ColorDialogManager {
    /// Dialog backend. Defaults to the real Win32 `ChooseColorW` dialog;
    /// tests inject a fake `ColorDialogProvider` and restore this afterwards.
    public static var provider: any ColorDialogProvider = Win32ColorDialogProvider()

    /// Shows the native color dialog seeded with `initial`; `nil` on cancel.
    public static func chooseColor(initial: Color) -> Color? {
        provider.chooseColor(initial: initial)
    }
}
