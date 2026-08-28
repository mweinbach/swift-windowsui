// Expected compilation failure. This directory is not a SwiftPM test target.
// See expected-diagnostics.json and README.md before interpreting an exit code.
import WinSwiftUI

@MainActor
@ViewBuilder
func canonicalOpaqueArrayRows(extras: [AnyView], loopValues: [Int]) -> [AnyView] {
    Text("Preceding sibling").accessibilityIdentifier("preceding")
    extras
    for value in loopValues {
        Text("Loop \(value)").accessibilityIdentifier("loop.\(value)")
    }
    Text("Following sibling").accessibilityIdentifier("following")
}

@MainActor
private func canonicalContent<Content: View>(@ViewBuilder _ content: () -> Content) -> Content {
    content()
}

@MainActor
private func canonicalRows(@ViewBuilder _ content: () -> [AnyView]) -> [AnyView] {
    content()
}

@MainActor
func canonicalOpaqueLoopClosures() {
    let typed = canonicalContent {
        for index in 0..<4 {
            if index.isMultiple(of: 2) {
                Text("typed \(index)").frame(width: 70, height: 10)
            }
        }
        Text("following").frame(width: 70, height: 10)
    }
    let rows = canonicalRows {
        for index in 0..<4 {
            if index.isMultiple(of: 2) {
                Text("array \(index)").frame(width: 70, height: 10)
            }
        }
    }
    let _ = (typed, rows)
}
