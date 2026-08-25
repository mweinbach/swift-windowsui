/// The actual semantic colors selected by a Windows high-contrast theme.
///
/// These roles live in the renderer-neutral core so platform sampling can
/// flow through the inherited view environment without teaching controls,
/// scenes, or renderers about Win32 color indexes.
public struct HighContrastSystemColors: Sendable, Equatable {
    public var windowBackground: Color
    public var windowText: Color
    public var controlBackground: Color
    public var controlText: Color
    public var selectedBackground: Color
    public var selectedText: Color
    public var disabledText: Color
    public var linkText: Color

    public init(
        windowBackground: Color,
        windowText: Color,
        controlBackground: Color,
        controlText: Color,
        selectedBackground: Color,
        selectedText: Color,
        disabledText: Color,
        linkText: Color
    ) {
        self.windowBackground = windowBackground
        self.windowText = windowText
        self.controlBackground = controlBackground
        self.controlText = controlText
        self.selectedBackground = selectedBackground
        self.selectedText = selectedText
        self.disabledText = disabledText
        self.linkText = linkText
    }

    /// High-contrast themes own their own dark/light identity; the unrelated
    /// Windows AppsUseLightTheme preference cannot describe a custom theme.
    public var prefersLightAppearance: Bool {
        let luminance =
            0.2126 * Double(windowBackground.red)
            + 0.7152 * Double(windowBackground.green)
            + 0.0722 * Double(windowBackground.blue)
        return luminance >= 0.5
    }
}
