import SwiftWindowsCore
import SwiftWindowsLayout
import SwiftWindowsPlatform
import SwiftWindowsRendererD3D11

@MainActor
public final class FoundationApp: WindowDelegate {
    private let window: Win32Window
    private let renderer: D3D11Renderer
    private let runtime: RetainedViewRuntime

    public init() {
        self.window = Win32Window(title: "Swift Windows UI", clientSize: IntSize(width: 1280, height: 720))
        self.renderer = D3D11Renderer()

        func installFocusablePalette(
            on node: ViewNode,
            idle: Color,
            focused: Color,
            pressed: Color,
            keyboardActivated: Color? = nil
        ) {
            node.isFocusable = true
            node.onFocusEnter = { [weak node] in
                node?.backgroundColor = focused
            }
            node.onFocusExit = { [weak node] in
                node?.backgroundColor = idle
            }
            node.onPointerDown = { [weak node] in
                node?.backgroundColor = pressed
            }
            node.onPointerUpInside = { [weak node] in
                node?.backgroundColor = focused
            }
            node.onPointerUpOutside = { [weak node] in
                node?.backgroundColor = focused
            }
            node.onActivate = { [weak node] in
                node?.backgroundColor = keyboardActivated ?? pressed
            }
        }

        let root = ViewNode()

        let heroCard = ViewNode(
            frame: Rect(x: 72, y: 80, width: 520, height: 320),
            backgroundColor: Color(red: 0.15, green: 0.20, blue: 0.28, alpha: 1.0),
            cornerRadius: 28,
            clipsToBounds: true
        )

        let heroGlow = ViewNode(
            frame: Rect(x: -32, y: 16, width: 320, height: 140),
            backgroundColor: Color(red: 0.30, green: 0.59, blue: 0.80, alpha: 0.92),
            cornerRadius: 18
        )

        let heroStripe = ViewNode(
            frame: Rect(x: 24, y: 156, width: 620, height: 32),
            backgroundColor: Color(red: 0.43, green: 0.71, blue: 0.86, alpha: 0.88),
            cornerRadius: 16
        )

        let sideRail = ViewNode(
            frame: Rect(x: 640, y: 80, width: 180, height: 520),
            backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 1.0),
            cornerRadius: 24,
            clipsToBounds: true
        )

        let sideAccent = ViewNode(
            frame: Rect(x: -28, y: 24, width: 220, height: 84),
            backgroundColor: Color(red: 0.96, green: 0.56, blue: 0.33, alpha: 1.0),
            cornerRadius: 18
        )

        let statusPill = ViewNode(
            frame: Rect(x: 864, y: 88, width: 280, height: 72),
            backgroundColor: Color(red: 0.22, green: 0.31, blue: 0.41, alpha: 0.96),
            cornerRadius: 36
        )

        let metricsPanel = ViewNode(
            frame: Rect(x: 864, y: 184, width: 280, height: 292),
            backgroundColor: Color(red: 0.13, green: 0.18, blue: 0.25, alpha: 0.98),
            cornerRadius: 26,
            clipsToBounds: true,
            layoutMode: .stack(
                .vertical(
                    spacing: 16,
                    padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                    alignment: .stretch
                )
            ),
            isHitTestVisible: false
        )

        let chipRow = ViewNode(
            layoutMode: .stack(.horizontal(spacing: 12, alignment: .stretch)),
            preferredSize: Size(width: 232, height: 48),
            isHitTestVisible: false
        )

        let chipA = ViewNode(
            backgroundColor: Color(red: 0.31, green: 0.46, blue: 0.60, alpha: 1.0),
            cornerRadius: 14,
            preferredSize: Size(width: 110, height: 48)
        )

        let chipB = ViewNode(
            backgroundColor: Color(red: 0.20, green: 0.62, blue: 0.55, alpha: 0.96),
            cornerRadius: 14,
            preferredSize: Size(width: 110, height: 48)
        )

        let metricCardA = ViewNode(
            backgroundColor: Color(red: 0.24, green: 0.34, blue: 0.45, alpha: 1.0),
            cornerRadius: 18,
            preferredSize: Size(width: 232, height: 64)
        )

        let metricCardB = ViewNode(
            backgroundColor: Color(red: 0.41, green: 0.54, blue: 0.72, alpha: 0.98),
            cornerRadius: 18,
            preferredSize: Size(width: 232, height: 56)
        )

        let metricCardC = ViewNode(
            backgroundColor: Color(red: 0.92, green: 0.68, blue: 0.29, alpha: 0.96),
            cornerRadius: 18,
            preferredSize: Size(width: 232, height: 44)
        )

        let statusIdleColor = Color(red: 0.22, green: 0.31, blue: 0.41, alpha: 0.96)
        let statusHoverColor = Color(red: 0.27, green: 0.40, blue: 0.52, alpha: 0.98)
        let statusPressedColor = Color(red: 0.96, green: 0.56, blue: 0.33, alpha: 1.0)
        installFocusablePalette(
            on: statusPill,
            idle: statusIdleColor,
            focused: statusHoverColor,
            pressed: statusPressedColor,
            keyboardActivated: Color(red: 0.77, green: 0.87, blue: 0.95, alpha: 1.0)
        )

        installFocusablePalette(
            on: chipA,
            idle: Color(red: 0.31, green: 0.46, blue: 0.60, alpha: 1.0),
            focused: Color(red: 0.39, green: 0.57, blue: 0.73, alpha: 1.0),
            pressed: Color(red: 0.64, green: 0.79, blue: 0.89, alpha: 1.0)
        )

        installFocusablePalette(
            on: chipB,
            idle: Color(red: 0.20, green: 0.62, blue: 0.55, alpha: 0.96),
            focused: Color(red: 0.28, green: 0.71, blue: 0.63, alpha: 1.0),
            pressed: Color(red: 0.74, green: 0.90, blue: 0.84, alpha: 1.0)
        )

        installFocusablePalette(
            on: metricCardA,
            idle: Color(red: 0.24, green: 0.34, blue: 0.45, alpha: 1.0),
            focused: Color(red: 0.34, green: 0.46, blue: 0.58, alpha: 1.0),
            pressed: Color(red: 0.56, green: 0.68, blue: 0.80, alpha: 1.0)
        )

        installFocusablePalette(
            on: metricCardB,
            idle: Color(red: 0.41, green: 0.54, blue: 0.72, alpha: 0.98),
            focused: Color(red: 0.49, green: 0.64, blue: 0.82, alpha: 1.0),
            pressed: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 1.0)
        )

        installFocusablePalette(
            on: metricCardC,
            idle: Color(red: 0.92, green: 0.68, blue: 0.29, alpha: 0.96),
            focused: Color(red: 0.97, green: 0.77, blue: 0.41, alpha: 1.0),
            pressed: Color(red: 1.0, green: 0.89, blue: 0.67, alpha: 1.0)
        )

        let footerBar = ViewNode(
            frame: Rect(x: 72, y: 440, width: 520, height: 96),
            backgroundColor: Color(red: 0.24, green: 0.30, blue: 0.37, alpha: 0.98),
            cornerRadius: 22
        )

        chipRow.addChild(chipA)
        chipRow.addChild(chipB)
        metricsPanel.addChild(chipRow)
        metricsPanel.addChild(metricCardA)
        metricsPanel.addChild(metricCardB)
        metricsPanel.addChild(metricCardC)
        heroCard.addChild(heroGlow)
        heroCard.addChild(heroStripe)
        sideRail.addChild(sideAccent)
        root.addChild(heroCard)
        root.addChild(sideRail)
        root.addChild(statusPill)
        root.addChild(metricsPanel)
        root.addChild(footerBar)

        self.runtime = RetainedViewRuntime(
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            root: root
        )

        self.window.delegate = self
    }

    @discardableResult
    public func run() throws -> Int32 {
        try Win32Application.run(window: window)
    }

    public func windowDidCreate(_ window: Win32Window) {
        do {
            guard let handle = window.nativeHandle else {
                return
            }

            try renderer.attach(
                to: SurfaceDescriptor(
                    windowHandle: handle,
                    pixelSize: window.currentClientSize(),
                    scaleFactor: window.scaleFactor
                )
            )
            runtime.setRootSize(window.currentClientSize())
            window.invalidate()
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.setRootSize(size)
            try renderer.resize(to: size)
            window.invalidate()
        } catch {
            report(error)
        }
    }

    public func windowNeedsDisplay(_ window: Win32Window) {
        do {
            try renderer.render(frame: runtime.renderFrame())
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, pointerMovedTo point: Point) {
        runtime.pointerMoved(to: point)
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        runtime.pointerDown(at: point)
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        runtime.pointerUp(at: point)
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        if runtime.isDirty {
            window.invalidate()
        }
    }

    public func windowWillClose(_ window: Win32Window) {}

    private func report(_ error: Error) {
        print("[SwiftWindowsUI] \(error)")
    }
}
