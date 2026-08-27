// Scoped, not `import Foundation`: corelibs-Foundation exports its own
// CG geometry types, and pulling the whole module in makes every
// `CGRect(x: a + b, …)` in the layout ambiguous enough to time out the
// type-checker. A scoped import still surfaces the member extensions
// (`.number` on `IntegerFormatStyle`) the settings form needs.
import struct Foundation.IntegerFormatStyle
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import struct Foundation.URL

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Backend-neutral presentation identity injected by the executable that owns
/// renderer selection. The shared dashboard never imports a graphics backend.
public struct DemoRendererIdentity: Hashable, Sendable {
    public let displayName: String
    public let componentDescription: String

    public init(displayName: String, componentDescription: String) {
        self.displayName = displayName
        self.componentDescription = componentDescription
    }

    public var readyEvent: String { "\(displayName) ready" }

    public static let direct3D11 = Self(
        displayName: "D3D11",
        componentDescription: "D3D11 batch pipeline"
    )

    public static let software = Self(
        displayName: "Software",
        componentDescription: "Software CPU presentation pipeline"
    )

    public static let nativeSwiftUI = Self(
        displayName: "SwiftUI",
        componentDescription: "Native SwiftUI presentation pipeline"
    )
}

@MainActor
public final class DemoDashboardModel: ObservableObject {
    public let rendererIdentity: DemoRendererIdentity

    @Published var selectedModule: DemoModule = .layout
    @Published var interactionCount = 0
    @Published var lastAction = "Ready"
    @Published var recentEvents: [String] = []

    /// Active top-level screen shown by the demo's `TabView` shell.
    @Published public var selectedScreen: DemoScreen = .dashboard {
        didSet {
            if selectedScreen != oldValue {
                performAction("Opened \(selectedScreen.label)")
            }
        }
    }

    // Gallery state belongs to the shared model so search and category
    // selection survive navigation while remaining deterministic in snapshots.
    @Published var selectedGalleryCategory: DemoGalleryCategory = .all
    @Published var galleryQuery = ""
    let galleryState = DemoGalleryState()

    // Settings screen state
    @Published var displayName = "Operator"
    @Published var theme: DemoThemeOption = .system
    @Published var itemsPerPage = 10 {
        didSet {
            guard itemsPerPage != oldValue else { return }
            reconcileComponentPageAndSelection()
        }
    }
    @Published var animationsEnabled = true
    @Published var soundEffectsEnabled = false
    @Published var shareUsageData = true
    @Published var fontScale = 1.0
    @Published var storageUsed = 0.62
    @Published var syncProgress = 0.35

    // Data screen state
    @Published public var components: [DemoComponent] = DemoComponent.defaults {
        didSet {
            reconcileComponentPageAndSelection()
        }
    }
    @Published public var selectedComponentID: Int? = DemoComponent.defaults.first?.id
    @Published private(set) var componentPage = 0
    @Published private(set) var componentSortColumn: DemoComponentSortColumn?
    @Published private(set) var componentSortDirection: DemoComponentSortDirection = .ascending
    @Published var componentFilter = "" {
        didSet {
            guard componentFilter != oldValue else { return }
            componentPage = 0
            reconcileFilteredComponentSelection()
        }
    }

    // Commands belong to the app shell, not to a toolbar that disappears at
    // narrow widths or when another top-level screen is selected.
    @Published var commandQuery = "" {
        didSet {
            guard commandQuery != oldValue else { return }
            selectedCommandIndex = 0
        }
    }
    @Published private(set) var isCommandPalettePresented = false
    @Published private(set) var selectedCommandIndex = 0
    @Published private(set) var isSidebarCollapsed = false
    @Published private(set) var isInspectorCollapsed = false
    @Published private(set) var hasSavedSettings = false
    @Published private(set) var settingsPersistenceError: String?

    // Integration surface state (color picker, file importer, drop target)
    @Published var accentColor: Color = DemoSignature.accentFill

    private var savedSettings = DemoSettingsSnapshot.defaults
    private let settingsStore: DemoSettingsStore

    public init(
        rendererIdentity: DemoRendererIdentity = .direct3D11,
        settingsStore: DemoSettingsStore = .inMemory()
    ) {
        self.rendererIdentity = rendererIdentity
        self.settingsStore = settingsStore
        recentEvents = [
            "System ready",
            rendererIdentity.readyEvent,
            "Window toolkit active",
        ]
        components = DemoComponent.defaults(for: rendererIdentity)
        selectedComponentID = components.first?.id
        restoreSettings()
    }

    /// Currently selected component on the data screen, if any.
    public var selectedComponent: DemoComponent? {
        components.first { $0.id == selectedComponentID }
    }

    /// Search every visible component attribute, accepting whitespace-separated
    /// terms in any order so "d3d11 render" is as useful as an exact name.
    var filteredComponents: [DemoComponent] {
        let terms = Self.searchTerms(in: componentFilter)
        let matches: [DemoComponent]
        if terms.isEmpty {
            matches = components
        } else {
            matches = components.filter { component in
                let searchableText = [
                    component.name,
                    component.detail,
                    component.version,
                    component.statusLabel,
                ]
                .joined(separator: " ")
                .lowercased()

                return terms.allSatisfy { searchableText.contains($0) }
            }
        }

        guard let componentSortColumn else { return matches }
        return matches.sorted { lhs, rhs in
            let comparison = componentSortColumn.comparison(lhs, rhs)
            if comparison == 0 {
                return lhs.id < rhs.id
            }
            return componentSortDirection == .ascending ? comparison < 0 : comparison > 0
        }
    }

    /// Filtering happens before pagination, so a match on a later component
    /// remains discoverable even when the current page is intentionally short.
    /// Keep at least one row available if the editable numeric field contains
    /// a transient zero or negative value between valid stepper selections.
    var displayedComponents: [DemoComponent] {
        let matchingComponents = filteredComponents
        let range = componentPageRange(in: matchingComponents.count)
        return Array(matchingComponents[range])
    }

    var componentPageCount: Int {
        let matchingCount = filteredComponents.count
        guard matchingCount > 0 else { return 1 }
        return 1 + (matchingCount - 1) / max(1, itemsPerPage)
    }

    var hasPreviousComponentPage: Bool {
        componentPage > 0
    }

    var hasNextComponentPage: Bool {
        componentPage + 1 < componentPageCount
    }

    var componentPageSummary: String {
        let matchingCount = filteredComponents.count
        guard matchingCount > 0 else { return "No components" }
        let range = componentPageRange(in: matchingCount)
        return "Showing \(range.lowerBound + 1)–\(range.upperBound) of \(matchingCount)"
    }

    /// The regular Dynamic Type size is exactly the existing demo baseline;
    /// the neighboring standard sizes make its Font Scale setting meaningful
    /// without introducing a Windows-only scaling API into shared app code.
    var dynamicTypeSize: DynamicTypeSize {
        switch fontScale {
        case ..<0.85:
            return .xSmall
        case ..<0.92:
            return .small
        case ..<0.98:
            return .medium
        case ..<1.06:
            return .large
        case ..<1.18:
            return .xLarge
        case ..<1.30:
            return .xxLarge
        default:
            return .xxxLarge
        }
    }

    var hasUnsavedSettings: Bool {
        settingsSnapshot != savedSettings
    }

    var isDisplayNameValid: Bool {
        displayName.contains { !$0.isWhitespace } && displayName.count <= 200
    }

    var settingsValidationMessage: String? {
        if displayName.count > 200 {
            return "Display name must be at most 200 characters"
        }
        if !isDisplayNameValid {
            return "Enter a display name before saving"
        }
        if !(1...100).contains(itemsPerPage) {
            return "Items per page must be between 1 and 100"
        }
        if !fontScale.isFinite || !(0.8...1.4).contains(fontScale) {
            return "Font scale must be between 80% and 140%"
        }
        return nil
    }

    var settingsStatusMessage: String {
        if let settingsValidationMessage { return settingsValidationMessage }
        if let settingsPersistenceError { return settingsPersistenceError }
        if hasUnsavedSettings {
            return "Unsaved changes"
        }
        return hasSavedSettings ? "All changes saved" : "Configure the demo shell"
    }

    var availableCommands: [DemoCommand] {
        var commands = DemoScreen.allCases.map { screen in
            DemoCommand(
                title: screen.label,
                subtitle: "Open the \(screen.label.lowercased()) screen",
                systemImage: screen.systemImage,
                keywords: screen.commandKeywords,
                destination: .screen(screen)
            )
        }

        commands.append(
            contentsOf: DemoModule.allCases.map { module in
                DemoCommand(
                    title: module.label,
                    subtitle: module.headline,
                    systemImage: module.systemImage,
                    keywords: [module.label, module.headline, module.summary, "module"],
                    destination: .module(module)
                )
            })

        commands.append(
            contentsOf: DemoModule.allCases.flatMap { module in
                module.actions.map { action in
                    DemoCommand(
                        title: action.title,
                        subtitle: action.caption,
                        systemImage: action.systemImage,
                        keywords: [action.title, action.caption, module.label, "action"],
                        destination: .moduleAction(module, action.eventLabel)
                    )
                }
            })

        commands.append(contentsOf: [
            DemoCommand(
                title: isSidebarCollapsed ? "Show sidebar" : "Hide sidebar",
                subtitle: "Toggle the workspace navigation column",
                systemImage: "rectangle.3.group",
                keywords: ["sidebar", "navigation", "workspace", "toggle"],
                destination: .toggleSidebar
            ),
            DemoCommand(
                title: isInspectorCollapsed ? "Show inspector" : "Hide inspector",
                subtitle: "Toggle the detail and quick-action column",
                systemImage: "info.circle",
                keywords: ["inspector", "details", "rail", "toggle"],
                destination: .toggleInspector
            ),
            DemoCommand(
                title: "Save settings",
                subtitle: "Save the current profile and preferences",
                systemImage: "gearshape",
                keywords: ["save", "settings", "preferences", "profile"],
                destination: .saveSettings
            ),
            DemoCommand(
                title: "Sync now",
                subtitle: "Advance synchronization progress",
                systemImage: "arrow.right",
                keywords: ["sync", "synchronize", "resources"],
                destination: .runSync
            ),
            DemoCommand(
                title: "Run component diagnostics",
                subtitle: "Inspect the selected component",
                systemImage: "waveform.path.ecg",
                keywords: ["run", "diagnose", "diagnostics", "component", "inspect"],
                destination: .runDiagnostics
            ),
            DemoCommand(
                title: "Restart selected component",
                subtitle: "Reduce load on the selected component",
                systemImage: "bolt.fill",
                keywords: ["restart", "component", "load", "health"],
                destination: .restartComponent
            ),
            DemoCommand(
                title: "Clear component filter",
                subtitle: "Show every component in the data table",
                systemImage: "xmark",
                keywords: ["clear", "filter", "search", "components", "data"],
                destination: .clearComponentFilter
            ),
        ])

        return commands
    }

    var matchingCommands: [DemoCommand] {
        let terms = Self.searchTerms(in: commandQuery)
        guard !terms.isEmpty else { return availableCommands }
        return availableCommands.filter { command in
            let searchableText = ([command.title, command.subtitle] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return terms.allSatisfy { searchableText.contains($0) }
        }
    }

    var selectedCommand: DemoCommand? {
        let matches = matchingCommands
        guard matches.indices.contains(selectedCommandIndex) else { return nil }
        return matches[selectedCommandIndex]
    }

    func selectScreen(_ screen: DemoScreen) {
        selectedScreen = screen
    }

    func saveSettings() {
        if let settingsValidationMessage {
            performAction(settingsValidationMessage)
            return
        }
        do {
            let record = settingsRecord
            try record.validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try settingsStore.save(encoder.encode(record))
            savedSettings = settingsSnapshot
            hasSavedSettings = true
            settingsPersistenceError = nil
            performAction("Saved settings for \(displayName)")
        } catch {
            settingsPersistenceError = "Could not save settings. Check the settings folder and try Save again."
            performAction("Settings save failed")
        }
    }

    private func restoreSettings() {
        do {
            guard let data = try settingsStore.load() else { return }
            let record = try JSONDecoder().decode(DemoSettingsRecord.self, from: data)
            try record.validate()
            displayName = record.displayName
            theme = DemoThemeOption(rawValue: record.theme) ?? .system
            itemsPerPage = record.itemsPerPage
            animationsEnabled = record.animationsEnabled
            soundEffectsEnabled = record.soundEffectsEnabled
            shareUsageData = record.shareUsageData
            fontScale = record.fontScale
            accentColor = Color(
                Color.Resolved(
                    red: record.accent.red, green: record.accent.green,
                    blue: record.accent.blue, opacity: record.accent.opacity))
            savedSettings = settingsSnapshot
            hasSavedSettings = true
        } catch {
            settingsPersistenceError = "Could not load settings. Defaults are shown; Save will replace the saved file."
        }
    }

    func resetSettings() {
        displayName = "Operator"
        theme = .system
        itemsPerPage = 10
        animationsEnabled = true
        soundEffectsEnabled = false
        shareUsageData = true
        fontScale = 1.0
        accentColor = DemoSignature.accentFill
        performAction("Reset settings to defaults")
    }

    func runSync() {
        syncProgress = min(1.0, syncProgress + 0.25)
        performAction(syncProgress >= 1.0 ? "Sync complete" : "Sync advanced")
    }

    func restartSelectedComponent() {
        guard let component = selectedComponent,
            let index = components.firstIndex(where: { $0.id == component.id })
        else {
            performAction("No component selected")
            return
        }

        components[index] = component.restarted()
        performAction("Restarted \(component.name)")
    }

    func runDiagnostics() {
        guard let component = selectedComponent else {
            performAction("No component selected")
            return
        }
        performAction("Diagnosed \(component.name)")
    }

    func selectFirstComponent() {
        selectedComponentID = displayedComponents.first?.id
    }

    func selectNextComponentPage() {
        guard hasNextComponentPage else { return }
        componentPage += 1
        reconcileFilteredComponentSelection()
        performAction("Opened component page \(componentPage + 1)")
    }

    func selectPreviousComponentPage() {
        guard hasPreviousComponentPage else { return }
        componentPage -= 1
        reconcileFilteredComponentSelection()
        performAction("Opened component page \(componentPage + 1)")
    }

    func selectComponent(_ component: DemoComponent) {
        selectedComponentID = component.id
        performAction("Selected \(component.name)")
    }

    func sortComponents(by column: DemoComponentSortColumn) {
        if componentSortColumn == column {
            componentSortDirection = componentSortDirection.reversed
        } else {
            componentSortColumn = column
            componentSortDirection = column.initialDirection
        }
        componentPage = 0
        reconcileFilteredComponentSelection()
        performAction("Sorted components by \(column.label.lowercased())")
    }

    func selectAdjacentComponent(offset: Int) {
        guard offset != 0 else { return }
        let matching = filteredComponents
        guard !matching.isEmpty else {
            selectedComponentID = nil
            return
        }

        guard let current = matching.firstIndex(where: { $0.id == selectedComponentID }) else {
            let index = offset > 0 ? 0 : matching.count - 1
            componentPage = index / max(1, itemsPerPage)
            selectComponent(matching[index])
            return
        }

        let target = min(max(current + offset, 0), matching.count - 1)
        guard target != current else { return }
        componentPage = target / max(1, itemsPerPage)
        selectComponent(matching[target])
    }

    func noteImportedFile(_ url: URL) {
        performAction("Imported \(url.lastPathComponent)")
    }

    func noteDroppedItems(count: Int) {
        performAction("Received \(count) dropped \(count == 1 ? "file" : "files")")
    }

    func selectModule(_ module: DemoModule) {
        selectedModule = module
        performAction("Selected \(module.label)")
    }

    func presentCommandPalette() {
        selectedCommandIndex = 0
        isCommandPalettePresented = true
    }

    func dismissCommandPalette() {
        isCommandPalettePresented = false
        commandQuery = ""
        selectedCommandIndex = 0
    }

    func moveCommandSelection(offset: Int) {
        guard !matchingCommands.isEmpty else {
            selectedCommandIndex = 0
            return
        }
        selectedCommandIndex = min(max(selectedCommandIndex + offset, 0), matchingCommands.count - 1)
    }

    func highlightCommand(at index: Int) {
        guard matchingCommands.indices.contains(index) else { return }
        selectedCommandIndex = index
    }

    func performCommand(_ command: DemoCommand) {
        switch command.destination {
        case .screen(let screen):
            selectScreen(screen)
        case .module(let module):
            selectScreen(.dashboard)
            selectModule(module)
        case .moduleAction(let module, let event):
            selectScreen(.dashboard)
            if selectedModule != module {
                selectModule(module)
            }
            performAction(event)
        case .toggleSidebar:
            isSidebarCollapsed.toggle()
            performAction(isSidebarCollapsed ? "Hid sidebar" : "Showed sidebar")
        case .toggleInspector:
            isInspectorCollapsed.toggle()
            performAction(isInspectorCollapsed ? "Hid inspector" : "Showed inspector")
        case .saveSettings:
            saveSettings()
        case .runSync:
            runSync()
        case .runDiagnostics:
            runDiagnostics()
        case .restartComponent:
            restartSelectedComponent()
        case .clearComponentFilter:
            clearComponentFilter()
            performAction("Cleared component filter")
        }

        dismissCommandPalette()
    }

    func runCommandSearch() {
        let terms = Self.searchTerms(in: commandQuery)
        guard !terms.isEmpty else { return }
        guard let command = selectedCommand else {
            performAction("No command found for \(commandQuery)")
            return
        }
        performCommand(command)
    }

    func clearComponentFilter() {
        componentFilter = ""
    }

    func cycleModule() {
        let modules = DemoModule.allCases
        guard let index = modules.firstIndex(of: selectedModule) else {
            return
        }

        let nextIndex = modules.index(after: index)
        selectedModule = nextIndex == modules.endIndex ? modules[modules.startIndex] : modules[nextIndex]
        performAction("Cycled \(selectedModule.label)")
    }

    func performAction(_ action: String) {
        interactionCount += 1
        lastAction = action
        recentEvents.insert(action, at: 0)
        if recentEvents.count > 10 {
            recentEvents.removeLast(recentEvents.count - 10)
        }
    }

    private func reconcileFilteredComponentSelection() {
        let visibleComponents = displayedComponents
        guard !visibleComponents.contains(where: { $0.id == selectedComponentID }) else { return }
        selectedComponentID = visibleComponents.first?.id
    }

    private func reconcileComponentPageAndSelection() {
        componentPage = min(componentPage, componentPageCount - 1)
        reconcileFilteredComponentSelection()
    }

    private func componentPageRange(in matchingCount: Int) -> Range<Int> {
        let pageSize = max(1, itemsPerPage)
        let lowerBound = min(componentPage * pageSize, matchingCount)
        let upperBound = lowerBound + min(pageSize, matchingCount - lowerBound)
        return lowerBound..<upperBound
    }

    private var settingsSnapshot: DemoSettingsSnapshot {
        DemoSettingsSnapshot(
            displayName: displayName,
            theme: theme,
            itemsPerPage: itemsPerPage,
            animationsEnabled: animationsEnabled,
            soundEffectsEnabled: soundEffectsEnabled,
            shareUsageData: shareUsageData,
            fontScale: fontScale,
            accentColor: accentColor
        )
    }

    private var settingsRecord: DemoSettingsRecord {
        let accent = accentColor.resolve(in: EnvironmentValues())
        return DemoSettingsRecord(
            displayName: displayName,
            theme: theme.rawValue,
            itemsPerPage: itemsPerPage,
            animationsEnabled: animationsEnabled,
            soundEffectsEnabled: soundEffectsEnabled,
            shareUsageData: shareUsageData,
            fontScale: fontScale,
            accent: .init(red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.opacity)
        )
    }

    private static func searchTerms(in query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map { String($0).lowercased() }
    }
}

private struct DemoSettingsSnapshot: Equatable, Sendable {
    let displayName: String
    let theme: DemoThemeOption
    let itemsPerPage: Int
    let animationsEnabled: Bool
    let soundEffectsEnabled: Bool
    let shareUsageData: Bool
    let fontScale: Double
    let accentColor: Color

    static let defaults = DemoSettingsSnapshot(
        displayName: "Operator",
        theme: .system,
        itemsPerPage: 10,
        animationsEnabled: true,
        soundEffectsEnabled: false,
        shareUsageData: true,
        fontScale: 1,
        accentColor: DemoSignature.accentFill
    )
}

enum DemoComponentSortDirection: Hashable {
    case ascending
    case descending

    var reversed: DemoComponentSortDirection {
        self == .ascending ? .descending : .ascending
    }

    var systemImage: String {
        self == .ascending ? "chevron.up" : "chevron.down"
    }

    var accessibilityLabel: String {
        self == .ascending ? "ascending" : "descending"
    }
}

enum DemoComponentSortColumn: CaseIterable, Hashable {
    case name
    case version
    case load
    case status

    var label: String {
        switch self {
        case .name: return "Component"
        case .version: return "Version"
        case .load: return "Load"
        case .status: return "Status"
        }
    }

    var initialDirection: DemoComponentSortDirection {
        switch self {
        case .name, .version:
            return .ascending
        case .load, .status:
            return .descending
        }
    }

    func comparison(_ lhs: DemoComponent, _ rhs: DemoComponent) -> Int {
        switch self {
        case .name:
            return Self.compare(lhs.name.lowercased(), rhs.name.lowercased())
        case .version:
            let left = Self.versionParts(lhs.version)
            let right = Self.versionParts(rhs.version)
            return (0..<max(left.count, right.count)).lazy.map { index in
                let lhsPart = index < left.count ? left[index] : 0
                let rhsPart = index < right.count ? right[index] : 0
                return Self.compare(lhsPart, rhsPart)
            }.first(where: { $0 != 0 }) ?? 0
        case .load:
            return Self.compare(lhs.load, rhs.load)
        case .status:
            return Self.compare(lhs.isHealthy ? 0 : 1, rhs.isHealthy ? 0 : 1)
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> Int {
        if lhs < rhs { return -1 }
        if lhs > rhs { return 1 }
        return 0
    }

    private static func versionParts(_ value: String) -> [Int] {
        value.drop(while: { !$0.isNumber }).split(separator: ".").map {
            Int($0) ?? 0
        }
    }
}

enum DemoCommandDestination: Hashable {
    case screen(DemoScreen)
    case module(DemoModule)
    case moduleAction(DemoModule, String)
    case toggleSidebar
    case toggleInspector
    case saveSettings
    case runSync
    case runDiagnostics
    case restartComponent
    case clearComponentFilter
}

struct DemoCommand: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let systemImage: String
    let keywords: [String]
    let destination: DemoCommandDestination

    var id: String {
        "\(title)|\(subtitle)"
    }
}

// MARK: - The signature

/// The app's whole chromatic personality, in five values.
///
/// "Quiet ink, one signature": the page is achromatic, and exactly one object
/// per screen is saturated. That object is filled with `heroGradient`, whose
/// first stop is always `accentFill` — only the second stop rotates per
/// module, so four modules read as four identities without ever becoming four
/// design languages. Everything else that needs the accent (bars, indicators,
/// meters, buttons) takes `accentFill` or the appearance's accent *ink*
/// (`DemoPalette.accentInk`), never a module tint.
///
/// Restyling the app later is a change to the five hexes below. No view may
/// write a violet of its own.
enum DemoSignature {
    /// Stop 1 of the signature gradient, and the accent **as an opaque fill**
    /// under white text: the same value in both appearances, because an
    /// opaque fill has no appearance behind it to vary with. White on it
    /// clears 5.9:1. (`ControlPalette.accentFill` / `Color.accentColor`.)
    static let accentFill = DemoPalette.hex(0x5B_4D_E0)

    /// Stop 2, per module. Every one of these clears 5:1 with white, so the
    /// hero's headline *and* its subtitle stay legible across the whole ramp.
    /// The signature written **on white** — the hero's inverse primary
    /// button, which is the strongest gesture the design has. 8.4:1 on white.
    static let accentInkOnWhite = DemoPalette.hex(0x3F_33_C6)

    static let layoutStop = DemoPalette.hex(0x2F_63_D8)
    static let inputStop = DemoPalette.hex(0x14_71_7E)
    static let animationStop = DemoPalette.hex(0xC0_39_7A)
    static let controlsStop = DemoPalette.hex(0x8A_3F_D4)
}

// MARK: - Design tokens

/// The design system's colour roles, resolved for one appearance.
///
/// This is the demo's portable mirror of `WinSwiftUI.ControlPalette`: the demo
/// is same-source with macOS SwiftUI and so cannot import the Windows control
/// palette, but it must not invent a second design system either.
/// `DemoDesignTokenParityTests` asserts every value below against the
/// corresponding `ControlPalette` / `DesignTokens` role, so the two tables
/// cannot drift — a token changed in the stack fails the demo's test until it
/// is changed here too.
///
/// Text is *not* here. The four text rungs are `.primary` / `.secondary` /
/// `.tertiary` / `.quaternary`, which the system resolves per appearance and
/// per contrast setting through the same `LabelHierarchy` machinery the
/// controls use.
struct DemoPalette {
    let colorScheme: ColorScheme

    init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }

    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A light-appearance wash, mixed from the page's own ink rather than
    /// from pure black: on a cool near-white page a pure-black hairline reads
    /// a shade warm, and `#0C0C0E` at the same alpha does not.
    static func ink(_ opacity: Double) -> Color { hex(0x0C_0C_0E, opacity) }

    /// A dark-appearance wash. Kept off the `LabelHierarchy` sentinel alphas
    /// (0.95 / 0.80 / 0.66 / 0.62 / 0.47 / 0.30 / 0.18 on pure white), which
    /// the appearance resolver reads as text rungs and would flip to ink in a
    /// light window.
    static func white(_ opacity: Double) -> Color {
        Color(red: 1, green: 1, blue: 1, opacity: opacity)
    }

    var isDark: Bool { colorScheme == .dark }

    private func pick(dark: Color, light: Color) -> Color { isDark ? dark : light }

    // MARK: Neutral ramp

    /// Every rung below is `rampStep` levels of 255 from the one beside it.
    /// The ramp this replaced stepped 5 to 8, and 6/255 at the dark end of the
    /// curve is under a percent of luminance: every elevation in the app was
    /// carried by its hairline alone, and a screenshot read as one flat
    /// near-black field with rules drawn on it.
    static let rampStep = 11

    /// **The frame.** Window backdrop, sidebar and rail columns, page gutters.
    /// In light the frame is the *cooler* of the two as well as the darker
    /// one, so a sidebar reads as shade rather than as grey paint.
    var base: Color { pick(dark: Self.hex(0x0C_0C_0E), light: Self.hex(0xE6_E8_EC)) }
    /// **The paper.** Content wells, scroll wells, table bodies — and the tone
    /// the chrome bands land on, so a toolbar reads as the top of the content
    /// rather than as a third slab stacked above it.
    var surface0: Color { pick(dark: Self.hex(0x17_17_1C), light: Self.hex(0xF1_F3_F6)) }
    /// **Cards.** The one and only card fill.
    var surface1: Color { pick(dark: Self.hex(0x22_22_27), light: Self.hex(0xFF_FF_FF)) }
    /// The card material's bottom stop — `surface1` three levels down. The
    /// travel is at the edge of perception, and that is exactly what separates
    /// a surface from a rectangle of paint: it is a *sheen*, not a rung, so it
    /// stays well inside `rampStep`.
    var surface1Bottom: Color { pick(dark: Self.hex(0x1F_1F_24), light: Self.hex(0xFB_FB_FC)) }
    /// Inside a card: fields, chips, icon tiles, segmented track, row hover.
    var surface2: Color { pick(dark: Self.hex(0x2D_2D_32), light: Self.hex(0xEB_ED_F0)) }
    /// Pressed / active / selected-neutral; menu and popover body.
    var surface3: Color { pick(dark: Self.hex(0x39_39_3E), light: Self.hex(0xDF_E1_E4)) }

    /// Hover fill of an item drawn straight onto the page tone — a nav row, a
    /// quick action, a tab. One rung either way from the frame, and the one
    /// token whose two columns move in *opposite* directions: on the
    /// near-black page the hover is a step up and reads as a lift, and on the
    /// near-white page there is no room above `base` for a step that size, so
    /// the light hover moves a rung *down* toward the ink instead.
    var pageItemHover: Color { pick(dark: Self.hex(0x17_17_1C), light: Self.hex(0xDB_DD_E0)) }

    // MARK: Hairlines

    /// Separators, table and form row rules, chart gridlines.
    var strokeSubtle: Color { pick(dark: Self.white(0.06), light: Self.ink(0.07)) }
    /// Card ring, chip ring, field ring.
    var stroke: Color { pick(dark: Self.white(0.09), light: Self.ink(0.10)) }
    /// Band edges, popover ring, control bezel, chart baseline.
    var strokeStrong: Color { pick(dark: Self.white(0.14), light: Self.ink(0.15)) }
    /// Top stop of every ring. A dark ring is brightest at the top; a light
    /// ring withdraws at the top and closes at the bottom — the same lighting
    /// read the other way round.
    var edgeHighlight: Color { pick(dark: Self.white(0.10), light: Self.white(0.75)) }

    // MARK: Accent — one accent, two roles

    /// The accent **as ink**: chart bars, selection indicators, active glyphs,
    /// meters, link text. It varies with the appearance behind it, because ink
    /// always does.
    var accentInk: Color { pick(dark: Self.hex(0x8B_7C_FF), light: Self.hex(0x5B_4D_E0)) }
    /// The accent **as an opaque fill** under white text.
    var accentFill: Color { DemoSignature.accentFill }
    /// The lightness move an accent fill makes for state. Never an alpha
    /// ramp: a "half-disabled" looking fill is what a wash reads as.
    var accentFillHovered: Color { Self.hex(0x6A_5D_E8) }
    var accentFillPressed: Color { Self.hex(0x4A_3E_C4) }
    /// Selected nav row, hovered chart column, tag chips.
    var accentWash: Color { accentInk.opacity(isDark ? 0.14 : 0.10) }
    /// Selected row in a focused list — one step up from `accentWash`.
    var accentWashStrong: Color { accentInk.opacity(isDark ? 0.20 : 0.15) }

    // MARK: Status

    /// Status rides a 6–7pt dot, a meter fill or 11pt chip text — never a
    /// large fill, never body text, never a button fill.
    var success: Color { pick(dark: Self.hex(0x3F_D0_8A), light: Self.hex(0x0B_7A_52)) }
    var warning: Color { pick(dark: Self.hex(0xF5_B9_3C), light: Self.hex(0xA4_5A_00)) }
    var danger: Color { pick(dark: Self.hex(0xFF_6F_6F), light: Self.hex(0xC6_2B_22)) }

    func statusWash(_ status: Color) -> Color { status.opacity(isDark ? 0.14 : 0.10) }

    // MARK: Content on a filled accent surface

    /// The label ladder rebased onto white. Written as literal alphas rather
    /// than as `.secondary` / `.tertiary` because the hero is the *same* card
    /// in both appearances: the semantic rungs would flip to ink in a light
    /// window and put dark text on a saturated card.
    var onAccentPrimary: Color { Self.white(1) }
    var onAccentSecondary: Color { Self.white(0.88) }
    var onAccentTertiary: Color { Self.white(0.65) }

    // MARK: Elevation

    /// **The appearance-conditional card rule.** In dark a card is `surface1`
    /// closed by a hairline and casts nothing — a shadow under a near-black
    /// card on a near-black page is invisible work, and at any visible alpha
    /// it fills the gutter beside the card with a smear instead of page tone.
    /// In light a white card on `#F2F3F5` takes `e1`: a 3pt blur at y 1 that
    /// reads as a paper lift.
    var cardShadow: Color { isDark ? Color.clear : Self.ink(0.06) }
    var cardShadowRadius: CGFloat { 3 }
    var cardShadowOffsetY: CGFloat { 1 }

    /// `e4` — the hero card only, and the one tinted shadow in the app.
    var heroShadow: Color { DemoSignature.accentFill.opacity(isDark ? 0.22 : 0.16) }
    var heroShadowRadius: CGFloat { isDark ? 28 : 24 }
    var heroShadowOffsetY: CGFloat { 10 }
}

/// The spacing, radius and row-height scales.
///
/// A 4/8 grid and nothing else is legal; no radius exceeds 12; a band that
/// touches a window edge is square and closed by a hairline. Mirrors
/// `MacOSControlMetrics.Spacing` / `.Radius`, pinned by the same parity test
/// as the colour table.
enum DemoMetrics {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64

    /// Chart bar caps, selection indicator bars, mini meters.
    static let radiusXS: CGFloat = 3
    /// Controls: button, field, segment pill, nav row, table row.
    static let radiusSM: CGFloat = 6
    /// Chip, icon tile, segmented track, badge.
    static let radiusMD: CGFloat = 8
    /// Cards, form section boxes.
    static let radiusLG: CGFloat = 10
    /// Hero, popover, menu, sheet.
    static let radiusXL: CGFloat = 12

    static let navRowHeight: CGFloat = 30
    static let listRowHeight: CGFloat = 36
    static let tableHeaderHeight: CGFloat = 32
    static let chipHeight: CGFloat = 22
    static let controlHeight: CGFloat = 28
    static let toolbarHeight: CGFloat = 48
    static let footerHeight: CGFloat = 64
    static let dataHeaderHeight: CGFloat = 56

    static let sidebarWidth: CGFloat = 220
    static let railWidth: CGFloat = 260
    static let settingsColumnWidth: CGFloat = 720

    /// Meter and progress track: 4 tall, fully rounded.
    static let meterThickness: CGFloat = 4
    /// A status dot.
    static let dotSize: CGFloat = 6
    /// The sanctioned icon tile — an empty state's glyph, the footer
    /// inspector's subject. Every *other* icon in the app is a bare glyph.
    static let iconTile: CGFloat = 28
}

/// The type ramp — Segoe UI Variable at 400 / 500 / 600 and nothing heavier.
///
/// **The weight axis is the hierarchy tool, not size.** `cardTitle` (14/600 on
/// the primary rung) and `body` (13/400 on the secondary rung) are one point
/// apart and read as clearly different roles, because weight *and* rung both
/// move. `design: .rounded` appears nowhere: rounded is a soft consumer voice,
/// and every app at this bar is set in a neutral grotesque.
enum DemoType {
    static var hero: Font { .system(size: 28, weight: .semibold) }
    static var screenTitle: Font { .system(size: 22, weight: .semibold) }
    static var titleSub: Font { .system(size: 13, weight: .regular) }
    static var section: Font { .system(size: 15, weight: .semibold) }
    static var cardTitle: Font { .system(size: 14, weight: .semibold) }
    static var metric: Font { Font.system(size: 26, weight: .semibold).monospacedDigit() }
    static var metricSmall: Font { Font.system(size: 18, weight: .semibold).monospacedDigit() }
    static var body: Font { .system(size: 13, weight: .regular) }
    static var bodyStrong: Font { .system(size: 13, weight: .medium) }
    static var bodySelected: Font { .system(size: 13, weight: .semibold) }
    static var controlLabel: Font { .system(size: 12, weight: .medium) }
    static var controlLabelStrong: Font { .system(size: 12, weight: .semibold) }
    static var caption: Font { .system(size: 11, weight: .regular) }
    static var captionStrong: Font { Font.system(size: 11, weight: .medium).monospacedDigit() }
    static var eyebrow: Font { .system(size: 11, weight: .semibold) }
    static var axis: Font { Font.system(size: 10, weight: .regular).monospacedDigit() }
    static var badge: Font { .system(size: 11, weight: .medium) }
    static var hint: Font { Font.system(size: 10, weight: .medium) }
    static var numeric: Font { Font.system(size: 11, weight: .semibold).monospacedDigit() }
}

// MARK: - Chrome atoms

/// A group eyebrow. The only uppercase role in the system, and it is set by
/// `.textCase(.uppercase)` on a sentence-case string so the system supplies
/// the tracking capitals need.
struct DemoEyebrow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(DemoType.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
}

/// A 1pt rule. Every structural edge in the app is one of these; nothing is
/// separated by a gutter between floating panels.
struct DemoRule: View {
    let color: Color
    let axis: Axis
    let length: CGFloat?

    enum Axis { case horizontal, vertical }

    init(_ color: Color, axis: Axis = .horizontal, length: CGFloat? = nil) {
        self.color = color
        self.axis = axis
        self.length = length
    }

    /// A rule with no stated length is **greedy**: a hairline that only
    /// stretches when its parent happens to stretch it is a hairline that
    /// silently measures zero — which is how four chart gridlines and the
    /// hero's lit edge came to be in the tree at 0pt wide.
    @ViewBuilder
    var body: some View {
        if axis == .vertical {
            color.frame(width: 1, height: length)
        } else if let length {
            color.frame(width: length, height: 1)
        } else {
            color.frame(height: 1).frame(maxWidth: .infinity)
        }
    }
}

/// The one and only card: `surface1` under a two-stop material, closed by a
/// top-lit hairline ring at `r-lg`, flat in dark and lifted by `e1` in light.
struct DemoCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    let padding: EdgeInsets
    let cornerRadius: CGFloat

    init(
        padding: CGFloat = DemoMetrics.s3,
        cornerRadius: CGFloat = DemoMetrics.radiusLG,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = EdgeInsets(
            top: padding, leading: padding, bottom: padding, trailing: padding)
        self.cornerRadius = cornerRadius
    }

    init(
        padding: EdgeInsets,
        cornerRadius: CGFloat = DemoMetrics.radiusLG,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        content
            .padding(padding)
            .background(
                LinearGradient(
                    colors: [palette.surface1, palette.surface1Bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(cornerRadius)
            .padding(1)
            .background(
                LinearGradient(
                    colors: [palette.edgeHighlight, palette.stroke],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(cornerRadius + 1)
            .shadow(
                color: palette.cardShadow,
                radius: palette.cardShadowRadius,
                x: 0,
                y: palette.cardShadowOffsetY
            )
    }
}

/// A bare monochrome glyph — the app's *only* icon treatment outside the two
/// sanctioned 28x28 tiles. It rests on the third text rung, promotes to the
/// second on hover, and takes accent ink when the object it names is the
/// active selection. Never a filled rounded-square chip.
struct DemoRowGlyph: View {
    let systemImage: String
    let size: CGFloat
    let accent: Color?
    let isHighlighted: Bool

    init(
        _ systemImage: String,
        size: CGFloat = 15,
        accent: Color? = nil,
        isHighlighted: Bool = false
    ) {
        self.systemImage = systemImage
        self.size = size
        self.accent = accent
        self.isHighlighted = isHighlighted
    }

    @ViewBuilder
    var body: some View {
        if let accent {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundColor(accent)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(isHighlighted ? .secondary : .tertiary)
        }
    }
}

/// A status dot. Colour rides a symbol, never a word and never a fill.
struct DemoStatusDot: View {
    let color: Color
    let size: CGFloat

    init(_ color: Color, size: CGFloat = DemoMetrics.dotSize) {
        self.color = color
        self.size = size
    }

    var body: some View {
        color
            .frame(width: size, height: size)
            .cornerRadius(size * 0.5)
    }
}

/// A 4pt meter. The track is the neutral recess, the fill is accent ink —
/// until the value is high enough that the *status* is the story.
struct DemoMeter: View {
    @Environment(\.colorScheme) private var colorScheme

    let value: Double
    let width: CGFloat

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    static func fillColor(for value: Double, palette: DemoPalette) -> Color {
        if value > 0.90 { return palette.danger }
        if value > 0.75 { return palette.warning }
        return palette.accentInk
    }

    var body: some View {
        let clamped = min(1, max(0, value))
        let thickness = DemoMetrics.meterThickness
        return ZStack(alignment: .leading) {
            palette.surface3
                .frame(width: width, height: thickness)
                .cornerRadius(thickness * 0.5)

            Self.fillColor(for: clamped, palette: palette)
                .frame(width: max(thickness, width * CGFloat(clamped)), height: thickness)
                .cornerRadius(thickness * 0.5)
        }
        .frame(width: width, height: thickness, alignment: .leading)
    }
}

/// The sanctioned 28x28 icon tile — an empty state's subject, the footer
/// inspector's subject. Every other icon in the app is a bare monochrome
/// glyph on the page.
struct DemoIconTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: DemoMetrics.iconTile, height: DemoMetrics.iconTile)
            .background(palette.surface2)
            .cornerRadius(DemoMetrics.radiusMD)
            .padding(1)
            .background(palette.stroke)
            .cornerRadius(DemoMetrics.radiusMD + 1)
    }
}

/// Every button in the demo, in the four shapes the design system has: a
/// neutral bordered chassis, the one accent fill, the hero's inverse white
/// primary, and a ghost on a saturated card.
///
/// A pressed control does not move: the fill and the label carry the whole
/// affordance.
struct DemoButton: View {
    enum Kind {
        case neutral
        case accent
        case inverse
        case ghost
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let title: String
    let kind: Kind
    let labelColor: Color?
    let horizontalPadding: CGFloat
    let perform: @MainActor @Sendable () -> Void

    init(
        _ title: String,
        kind: Kind = .neutral,
        labelColor: Color? = nil,
        horizontalPadding: CGFloat = DemoMetrics.s3,
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.labelColor = labelColor
        self.horizontalPadding = horizontalPadding
        self.perform = perform
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var fill: Color {
        switch kind {
        case .neutral:
            return isHovering ? palette.surface3 : palette.surface2
        case .accent:
            return isHovering ? palette.accentFillHovered : palette.accentFill
        case .inverse:
            // Appearance-independent, like the card it sits on: the hero is
            // the same object in both appearances, so its buttons are too.
            return isHovering ? DemoPalette(colorScheme: .light).base : DemoPalette.white(1)
        case .ghost:
            return DemoPalette.white(isHovering ? 0.22 : 0.14)
        }
    }

    private var ring: Color {
        switch kind {
        case .neutral: return palette.strokeStrong
        case .accent: return palette.accentFill
        case .inverse: return DemoPalette.white(0.9)
        case .ghost: return DemoPalette.white(0.24)
        }
    }

    /// The label colour, when it is a colour. A neutral button's label is the
    /// *primary text rung* — a semantic style, not a value — so that branch
    /// returns nil and the label is written with `.foregroundStyle(.primary)`.
    private var foreground: Color? {
        if let labelColor { return labelColor }
        switch kind {
        case .neutral: return nil
        case .accent: return DemoPalette.white(1)
        // The strongest gesture in the app, and it costs nothing: a white
        // fill with the signature in the label.
        case .inverse: return DemoSignature.accentInkOnWhite
        case .ghost: return DemoPalette.white(1)
        }
    }

    private var font: Font {
        kind == .neutral ? DemoType.controlLabel : DemoType.controlLabelStrong
    }

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: 0) {
                if let foreground {
                    Text(title)
                        .font(font)
                        .foregroundColor(foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                } else {
                    Text(title)
                        .font(font)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: DemoMetrics.controlHeight)
            .background(fill)
            .cornerRadius(DemoMetrics.radiusSM)
            .padding(1)
            .background(ring)
            .cornerRadius(DemoMetrics.radiusSM + 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Shell

public struct DemoRootView: View {
    @ObservedObject var model: DemoDashboardModel
    // The WindowGroup creates this root once per window. Keep its readout
    // ownership above tabs that rebuild or remove their child view values.
    @StateObject private var windowState = DemoWindowState()

    public init(model: DemoDashboardModel) {
        self.model = model
    }

    /// Product-style shell: a tab bar navigates between the dashboard,
    /// settings, data list, and interactive gallery using same-source APIs.
    public var body: some View {
        TabView(selection: $model.selectedScreen) {
            DemoDashboardScreen(model: model)
                .tabItem {
                    Label(DemoScreen.dashboard.label, systemImage: DemoScreen.dashboard.systemImage)
                }
                .tag(DemoScreen.dashboard)

            DemoSettingsScreen(model: model)
                .tabItem {
                    Label(DemoScreen.settings.label, systemImage: DemoScreen.settings.systemImage)
                }
                .tag(DemoScreen.settings)

            DemoDataScreen(model: model)
                .tabItem {
                    Label(DemoScreen.data.label, systemImage: DemoScreen.data.systemImage)
                }
                .tag(DemoScreen.data)

            DemoGalleryScreen(model: model)
                .environmentObject(windowState)
                .tabItem {
                    Label(DemoScreen.gallery.label, systemImage: DemoScreen.gallery.systemImage)
                }
                .tag(DemoScreen.gallery)
        }
        .preferredColorScheme(model.theme.colorScheme)
        .tint(model.accentColor)
        .dynamicTypeSize(model.dynamicTypeSize)
        // The standard Settings shortcut uses the retained command path, so
        // modal isolation applies just as it does to other view shortcuts.
        .background(alignment: .topLeading) {
            SettingsLink {
                Color.clear
            }
            .keyboardShortcut(",", modifiers: .command)
            .focusable(false)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        // Keep the shortcut mounted outside every tab and every responsive
        // toolbar branch. A transparent one-point command target contributes
        // neither chrome nor a stray accessibility/focus stop.
        .background(alignment: .topLeading) {
            Button(action: {
                model.presentCommandPalette()
            }) {
                Color.clear
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .focusable(false)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        // Gallery discovery stays available from the keyboard without adding
        // chrome to the dashboard or disturbing its responsive breakpoints.
        .background(alignment: .topLeading) {
            Button(action: {
                model.selectScreen(.gallery)
            }) {
                Color.clear
            }
            .buttonStyle(.plain)
            .keyboardShortcut("g", modifiers: .command)
            .focusable(false)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        .overlay(alignment: .topLeading) {
            if model.isCommandPalettePresented {
                DemoCommandPaletteOverlay(model: model)
            }
        }
    }
}

/// A true app-wide command surface. It is intentionally composed from the
/// same portable SwiftUI shapes as every screen: Windows-specific keyboard
/// routing stays in the retained runtime rather than leaking into demo code.
struct DemoCommandPaletteOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let paletteWidth = min(560, max(360, proxy.size.width - DemoMetrics.s6 * 2))
            let topInset = min(96, max(DemoMetrics.s5, proxy.size.height * 0.13))
            let maximumResultsHeight = max(100, min(312, proxy.size.height - topInset - 112))

            ZStack(alignment: .top) {
                Color.black.opacity(0.46)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .onTapGesture {
                        model.dismissCommandPalette()
                    }

                DemoCommandPalette(
                    model: model,
                    width: paletteWidth,
                    maximumResultsHeight: maximumResultsHeight
                )
                .frame(width: paletteWidth, alignment: .leading)
                .padding(.top, topInset)
                .shadow(
                    color: palette.heroShadow,
                    radius: palette.heroShadowRadius,
                    x: 0,
                    y: palette.heroShadowOffsetY
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .zIndex(20)
        .presentationBackgroundInteraction(.disabled)
    }
}

struct DemoCommandPalette: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isQueryFocused: Bool
    @ObservedObject var model: DemoDashboardModel
    let width: CGFloat
    let maximumResultsHeight: CGFloat

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: 0, cornerRadius: DemoMetrics.radiusXL) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)

                    TextField("Search commands and actions", text: $model.commandQuery)
                        .font(DemoType.bodyStrong)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused($isQueryFocused)
                        .onSubmit {
                            if let selected = model.selectedCommand {
                                model.performCommand(selected)
                            }
                        }
                        .onMoveCommand { direction in
                            switch direction {
                            case .up:
                                model.moveCommandSelection(offset: -1)
                            case .down:
                                model.moveCommandSelection(offset: 1)
                            default:
                                break
                            }
                        }
                        .onExitCommand {
                            model.dismissCommandPalette()
                        }

                    Button(action: { model.dismissCommandPalette() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: DemoMetrics.controlHeight, height: DemoMetrics.controlHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close command palette")
                }
                .padding(.horizontal, DemoMetrics.s4)
                .frame(height: 54)

                DemoRule(palette.strokeSubtle, length: width - 2)

                if model.matchingCommands.isEmpty {
                    VStack(alignment: .center, spacing: DemoMetrics.s2) {
                        Text("No matching commands")
                            .font(DemoType.cardTitle)
                            .foregroundStyle(.primary)

                        Text("Try a screen, module, or action")
                            .font(DemoType.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: width - 2, height: 112, alignment: .center)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                                ForEach(Array(model.matchingCommands.enumerated()), id: \.element.id) {
                                    entry in
                                    DemoCommandPaletteRow(
                                        command: entry.element,
                                        isSelected: entry.offset == model.selectedCommandIndex
                                    ) {
                                        model.performCommand(entry.element)
                                    }
                                    .id(entry.element.id)
                                    .onHover { hovering in
                                        if hovering {
                                            model.highlightCommand(at: entry.offset)
                                        }
                                    }
                                }
                            }
                            .padding(DemoMetrics.s2)
                            .frame(width: width - 2, alignment: .leading)
                        }
                        .frame(width: width - 2, height: resultListHeight, alignment: .topLeading)
                        .onChange(of: model.selectedCommandIndex) { selectedIndex in
                            let matches = model.matchingCommands
                            guard matches.indices.contains(selectedIndex) else { return }
                            scrollProxy.scrollTo(matches[selectedIndex].id, anchor: .center)
                        }
                    }
                }

                DemoRule(palette.strokeSubtle, length: width - 2)

                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    Text("Up / Down to navigate")
                        .font(DemoType.caption)
                        .foregroundStyle(.tertiary)

                    Spacer(minLength: DemoMetrics.s2)

                    Text("Enter to run")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.secondary)

                    Text("Esc to close")
                        .font(DemoType.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DemoMetrics.s4)
                .frame(height: 38)
                .background(palette.surface2.opacity(0.45))
            }
            .frame(width: width - 2, alignment: .leading)
        }
        .onAppear {
            isQueryFocused = true
        }
    }

    private var resultListHeight: CGFloat {
        min(
            maximumResultsHeight,
            CGFloat(model.matchingCommands.count) * 46
                + CGFloat(max(0, model.matchingCommands.count - 1)) * DemoMetrics.s1
                + DemoMetrics.s2 * 2
        )
    }
}

struct DemoCommandPaletteRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let command: DemoCommand
    let isSelected: Bool
    let perform: @MainActor @Sendable () -> Void

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: DemoMetrics.s3) {
                DemoRowGlyph(command.systemImage, accent: isSelected ? palette.accentInk : nil)

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(isSelected ? DemoType.bodyStrong : DemoType.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(command.subtitle)
                        .font(DemoType.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Text("Enter")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, DemoMetrics.s3)
            .frame(height: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.accentWash : Color.clear)
            .cornerRadius(DemoMetrics.radiusSM)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(command.title), \(command.subtitle)")
    }
}

// MARK: - Dashboard

/// The control-center dashboard: two chrome bands on the page tone, then
/// three columns separated by full-height hairlines.
///
/// Nothing here is a floating panel. The sidebar and the rail are *columns* —
/// no fill, no ring, no corner — and the only thing between them and the
/// content is a 1px rule. That is what stops the shell reading as three
/// stacked rounded slabs.
struct DemoDashboardScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let layout = DemoLayout(
                size: proxy.size,
                isSidebarCollapsed: model.isSidebarCollapsed,
                isInspectorCollapsed: model.isInspectorCollapsed
            )

            VStack(alignment: .leading, spacing: 0) {
                DemoToolbar(model: model, layout: layout)

                // Only the columns the window can actually hold. What a
                // dropped column carried is not dropped with it — the centre
                // pane picks it up (see `DemoCenterPane`), so a narrow window
                // is a re-flow rather than a truncation.
                HStack(alignment: .top, spacing: 0) {
                    if layout.showsSidebar {
                        DemoSidebar(model: model, layout: layout)
                            .frame(
                                width: layout.sidebarWidth, height: layout.bodyHeight,
                                alignment: .topLeading)

                        DemoRule(palette.strokeSubtle, axis: .vertical, length: layout.bodyHeight)
                    }

                    DemoCenterPane(model: model, layout: layout)
                        .frame(width: layout.contentWidth, height: layout.bodyHeight, alignment: .topLeading)

                    if layout.showsRail {
                        DemoRule(palette.strokeSubtle, axis: .vertical, length: layout.bodyHeight)

                        DemoRightRail(model: model, layout: layout)
                            .frame(width: layout.railWidth, height: layout.bodyHeight, alignment: .topLeading)
                    }
                }
                .frame(height: layout.bodyHeight, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(palette.base)
        }
    }
}

/// The toolbar band: 48 tall, on the `.bar` material, closed by a structural
/// hairline, and carrying exactly one chromatic object (the module glyph) and
/// one status hue (a 6pt dot).
struct DemoToolbar: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DemoMetrics.s3) {
                // One line. The "Same-source dashboard demo" subtitle this
                // used to carry forced the band to 72pt and said nothing.
                Text("WinSwiftUI")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if layout.showsToolbarSearch {
                    DemoSearchField(model: model, width: layout.searchWidth)
                }

                Spacer(minLength: 0)

                if layout.showsToolbarStatusPills {
                    DemoToolbarChip {
                        HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                            DemoStatusDot(palette.success)

                            Text(model.rendererIdentity.displayName)
                                .font(DemoType.captionStrong)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    DemoToolbarChip {
                        HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                            Text("Events")
                                .font(DemoType.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)

                            Text("\(model.interactionCount)")
                                .font(DemoType.numeric)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }

                DemoModeButton(model: model)
            }
            // The band's own content width, stated once: a row with a
            // `Spacer` needs a definite width to distribute, and without it
            // every intrinsic child in the band is measured against a
            // proposal it never sees.
            .frame(width: layout.toolbarContentWidth, alignment: .leading)
            .padding(.horizontal, DemoMetrics.s4)
            .frame(height: DemoMetrics.toolbarHeight)
            .background(.bar)

            DemoRule(palette.strokeStrong, length: layout.size.width)
        }
    }
}

/// A toolbar chip: not a pill button, because it is not a button. 22 tall,
/// `r-md`, the recess fill and the card ring, intrinsic width.
///
/// The caller supplies its own `HStack`. A container that re-wraps a
/// `@ViewBuilder` result in a stack of its own turns N children into one
/// opaque view, and the layout that view gets is *absolute* — every child at
/// the same origin. That is what drew "Events" and its count on top of each
/// other.
struct DemoToolbarChip<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        content
            .padding(.horizontal, DemoMetrics.s2)
            .frame(height: DemoMetrics.chipHeight)
            .background(palette.surface2)
            .cornerRadius(DemoMetrics.radiusMD)
            .padding(1)
            .background(palette.stroke)
            .cornerRadius(DemoMetrics.radiusMD + 1)
    }
}

/// The one clickable thing on the band, so the only thing shaped like a
/// button.
struct DemoModeButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: { model.cycleModule() }) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                Image(systemName: model.selectedModule.systemImage)
                    .font(.system(size: 12))
                    .foregroundColor(palette.accentInk)

                Text(model.selectedModule.label)
                    .font(DemoType.controlLabel)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DemoMetrics.s3)
            .frame(height: DemoMetrics.controlHeight)
            .background(isHovering ? palette.surface3 : palette.surface2)
            .cornerRadius(DemoMetrics.radiusSM)
            .padding(1)
            .background(palette.strokeStrong)
            .cornerRadius(DemoMetrics.radiusSM + 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// The toolbar's search field. A recess with a ring, a glyph, a placeholder
/// and the shortcut hint — the shape every command palette in this class of
/// app has.
struct DemoSearchField: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: DemoDashboardModel
    let width: CGFloat

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Button(action: { model.presentCommandPalette() }) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open command palette")

            TextField("Search commands", text: $model.commandQuery)
                .font(DemoType.controlLabel)
                .textFieldStyle(.plain)
                .frame(width: max(96, width - 96), alignment: .leading)
                .onSubmit {
                    model.runCommandSearch()
                }

            if model.commandQuery.isEmpty {
                Text("Ctrl K")
                    .font(DemoType.hint)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .padding(.horizontal, DemoMetrics.s1)
                    .frame(height: DemoMetrics.s4)
                    .background(palette.surface3)
                    .cornerRadius(DemoMetrics.radiusXS)
            } else {
                Button(action: { model.commandQuery = "" }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: DemoMetrics.s5, height: DemoMetrics.s5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear command search")
            }
        }
        .padding(.horizontal, DemoMetrics.s2 + 2)
        .frame(width: width, height: DemoMetrics.controlHeight)
        .background(palette.surface2)
        .cornerRadius(DemoMetrics.radiusSM)
        .padding(1)
        .background(palette.stroke)
        .cornerRadius(DemoMetrics.radiusSM + 1)
    }
}

/// The sidebar column. Not a panel: no container, no fill, no corner — only
/// the page tone and a rule on its trailing edge.
struct DemoSidebar: View {
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DemoEyebrow("Workspace")
                    .padding(.leading, DemoMetrics.s3)
                    .padding(.bottom, DemoMetrics.s2)

                DemoNavList(model: model)

                // 24 above, 8 below: an eyebrow belongs to what is *under*
                // it, and the 3:1 ratio is what stops a section header
                // floating between two groups.
                DemoEyebrow("Session")
                    .padding(.top, DemoMetrics.s6)
                    .padding(.leading, DemoMetrics.s3)
                    .padding(.bottom, DemoMetrics.s2)

                DemoSessionRows(model: model)
            }
            .frame(width: layout.sidebarInnerWidth, alignment: .leading)
            .padding(DemoMetrics.s3)
        }
    }
}

struct DemoNavList: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(DemoModule.allCases, id: \.self) { module in
                DemoNavRow(
                    systemImage: module.systemImage,
                    title: module.label,
                    isSelected: model.selectedModule == module
                ) {
                    model.selectModule(module)
                }
            }
        }
    }
}

/// A navigation row: 30 tall, transparent at rest, an accent wash and a
/// 3x14 leading indicator when selected. No fill of its own, ever.
struct DemoNavRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let systemImage: String
    let title: String
    let isSelected: Bool
    let perform: @MainActor @Sendable () -> Void

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var fill: Color {
        if isSelected { return palette.accentWash }
        return isHovering ? palette.pageItemHover : Color.clear
    }

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: 0) {
                // The indicator, pinned to the row's leading edge.
                (isSelected ? palette.accentInk : Color.clear)
                    .frame(width: 3, height: 14)
                    .cornerRadius(DemoMetrics.radiusXS)

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoRowGlyph(
                        systemImage,
                        accent: isSelected ? palette.accentInk : nil,
                        isHighlighted: isHovering
                    )

                    Text(title)
                        .font(isSelected ? DemoType.bodySelected : DemoType.bodyStrong)
                        .foregroundStyle(isSelected || isHovering ? .primary : .secondary)
                        .lineLimit(1)
                }
                .padding(.leading, DemoMetrics.s2 - 1)

                Spacer(minLength: 0)
            }
            .padding(.leading, DemoMetrics.radiusXS)
            .frame(height: DemoMetrics.navRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .cornerRadius(DemoMetrics.radiusSM)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// The sidebar's second group — session status rather than navigation. Two
/// plain key/value rows: no card, no icon chip, no accent slab. It lives on
/// its own so the centre pane can host it verbatim in a window too narrow for
/// a sidebar.
struct DemoSessionRows: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DemoSessionRow(dot: palette.success, title: "State", value: model.lastAction)
            DemoSessionRow(dot: nil, title: "Shortcuts", value: "Tab · Wheel")
        }
    }
}

struct DemoSessionRow: View {
    let dot: Color?
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            // The dot column is reserved whether or not there is a dot. Two
            // key/value rows whose keys start at different x is the kind of
            // thing nobody consciously notices and everybody reads as sloppy.
            if let dot {
                DemoStatusDot(dot)
            } else {
                Color.clear
                    .frame(width: DemoMetrics.dotSize, height: DemoMetrics.dotSize)
            }

            Text(title)
                .font(DemoType.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: DemoMetrics.s2)

            Text(value)
                .font(DemoType.captionStrong)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, DemoMetrics.s3)
        .frame(height: DemoMetrics.navRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The module list, laid out the way a narrow window wants it: one scrolling
/// row of nav chips above the content instead of a column beside it.
struct DemoModuleStrip: View {
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            DemoEyebrow("Workspace")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    ForEach(DemoModule.allCases, id: \.self) { module in
                        DemoNavRow(
                            systemImage: module.systemImage,
                            title: module.label,
                            isSelected: model.selectedModule == module
                        ) {
                            model.selectModule(module)
                        }
                        .frame(width: layout.moduleChipWidth, alignment: .leading)
                    }
                }
            }
            .frame(height: DemoMetrics.navRowHeight + 2)
        }
    }
}

/// The centre column: the page's content well, an ambience band behind it,
/// and the page margin inside it.
struct DemoCenterPane: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.surface0
                .frame(width: layout.contentWidth, height: layout.bodyHeight)

            // One band, no shape, no edge that can read as a clipping bug.
            // (The two blurred rounded rects this replaced straddled the
            // gutters and read as bright slivers with hard edges.)
            LinearGradient(
                colors: [palette.accentInk.opacity(0.055), palette.accentInk.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: layout.contentWidth, height: layout.ambienceHeight)
            .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: layout.sectionGap) {
                    // Whatever the shell could not fit beside this column
                    // arrives here instead of disappearing.
                    if !layout.showsSidebar {
                        DemoModuleStrip(model: model, layout: layout)
                            .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }

                    DemoHeroCard(model: model, layout: layout)
                        .frame(width: layout.contentInnerWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: layout.cardGap) {
                        DemoChartCard(model: model, layout: layout)
                            .frame(width: layout.contentInnerWidth, alignment: .leading)

                        DemoStatBand(model: model, layout: layout)
                            .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }

                    // The live feed belongs to the dashboard, not to the
                    // folded-away rail. Keeping it before relocated detail
                    // content makes recent actions discoverable at widths
                    // where the rail no longer has a column of its own.
                    DemoActivityCard(model: model, compact: layout.verticallyCompact)
                        .frame(width: layout.contentInnerWidth, alignment: .leading)

                    if !layout.showsRail {
                        DemoDetailTrackSection(model: model, width: layout.contentInnerWidth)
                        DemoQuickActionsSection(model: model, width: layout.contentInnerWidth)
                    }

                    if !layout.showsSidebar {
                        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                            DemoEyebrow("Session")

                            DemoSessionRows(model: model)
                        }
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }
                }
                .padding(layout.pageMargin)
            }
            .frame(width: layout.contentWidth, height: layout.bodyHeight, alignment: .topLeading)
        }
    }
}

/// The hero — the one saturated object on the screen, and the only gradient
/// in the app.
///
/// The card is **identical in light and dark**: an opaque fill has no
/// appearance behind it to vary with, and that single decision is what makes
/// the light appearance a true sibling rather than a paler cousin.
struct DemoHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The lit edge. A saturated card needs no outer ring — a ring is
            // what made it read as pasted on — but it does need to look lit,
            // and a 1px inset highlight along the top is that.
            DemoPalette.white(0.2)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DemoMetrics.radiusXL)

            VStack(alignment: .leading, spacing: 0) {
                Text("Control center")
                    .font(DemoType.eyebrow)
                    .textCase(.uppercase)
                    .foregroundColor(palette.onAccentTertiary)
                    .lineLimit(1)

                Text(model.selectedModule.headline)
                    .font(DemoType.hero)
                    .tracking(0.35)
                    .foregroundColor(palette.onAccentPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.top, layout.verticallyCompact ? DemoMetrics.s2 : DemoMetrics.s3)

                Text(model.selectedModule.summary)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(palette.onAccentSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .padding(.top, layout.verticallyCompact ? DemoMetrics.s1 : DemoMetrics.s1 + 2)

                HStack(alignment: .center, spacing: DemoMetrics.s2 + 2) {
                    DemoButton(
                        "Open \(model.selectedModule.label)",
                        kind: .inverse,
                        horizontalPadding: DemoMetrics.s4
                    ) {
                        model.performAction("Opened \(model.selectedModule.label)")
                    }
                    .layoutPriority(1)

                    DemoButton("Cycle mode", kind: .ghost, horizontalPadding: DemoMetrics.s4 - 2) {
                        model.cycleModule()
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .padding(.top, layout.verticallyCompact ? DemoMetrics.s3 : DemoMetrics.s5)
            }
            .padding(layout.heroContentPadding)
        }
        // `minHeight`, not `height`: a compact window earns a tighter
        // presentation, never a fixed box that squeezes its controls. The
        // existing 172pt rhythm remains the spacious-window contract.
        .frame(minHeight: layout.presentationHeroHeight, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [DemoSignature.accentFill, model.selectedModule.signatureStop],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(DemoMetrics.radiusXL)
        .shadow(
            color: palette.heroShadow,
            radius: palette.heroShadowRadius,
            x: 0,
            y: palette.heroShadowOffsetY
        )
    }
}

/// Three stat cards across, 12 apart. No icon chip, no accent, no gradient,
/// no per-card tint: an eyebrow, a tabular metric, and a delta.
struct DemoStatBand: View {
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    @ViewBuilder
    var body: some View {
        if layout.stacksMetrics {
            VStack(alignment: .leading, spacing: layout.cardGap) {
                ForEach(cards, id: \.title) { card in
                    DemoStatCard(card: card, compact: layout.verticallyCompact)
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                }
            }
        } else {
            HStack(alignment: .top, spacing: layout.cardGap) {
                ForEach(cards, id: \.title) { card in
                    DemoStatCard(card: card, compact: layout.verticallyCompact)
                        .frame(width: layout.statCardWidth, alignment: .leading)
                }
            }
        }
    }

    private var cards: [DemoStat] {
        [
            DemoStat(
                title: "Interactions",
                systemImage: "bolt.fill",
                value: "\(model.interactionCount)",
                delta: model.interactionCount > 0 ? .up("12%") : .flat,
                note: "vs last run"
            ),
            DemoStat(
                title: "Module",
                systemImage: model.selectedModule.systemImage,
                value: model.selectedModule.label,
                delta: .flat,
                note: model.selectedModule.detailLine
            ),
            DemoStat(
                title: "Frame time",
                systemImage: "chart.bar",
                value: "0.6",
                delta: .improved("4%"),
                note: "ms per frame"
            ),
        ]
    }
}

struct DemoStat {
    enum Delta {
        /// A rise in a metric where more is better.
        case up(String)
        /// A fall in a metric where more is better.
        case down(String)
        /// A fall in a metric where *less* is better — frame cost, latency.
        /// The arrow points down and the hue still says "good", because the
        /// colour reports the news rather than the direction.
        case improved(String)
        case flat
    }

    let title: String
    let systemImage: String
    let value: String
    let delta: Delta
    let note: String
}

struct DemoStatCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let card: DemoStat
    let compact: Bool

    init(card: DemoStat, compact: Bool = false) {
        self.card = card
        self.compact = compact
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: compact ? DemoMetrics.s3 : DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    Image(systemName: card.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)

                    DemoEyebrow(card.title)
                }

                Text(card.value)
                    .font(compact ? DemoType.metricSmall : DemoType.metric)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, compact ? DemoMetrics.s1 + 2 : DemoMetrics.s2 + 2)

                HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                    DemoDeltaLabel(delta: card.delta)

                    Text(card.note)
                        .font(DemoType.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.top, compact ? DemoMetrics.s1 : DemoMetrics.s1 + 2)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: compact ? 88 : 104, alignment: .topLeading)
    }
}

struct DemoDeltaLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let delta: DemoStat.Delta

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    /// A delta is a 7pt triangle and a 10/600 label in the status hue — no
    /// fill, no chip, no pill.
    @ViewBuilder
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 7))
                    .foregroundColor(tint)

                Text(amount)
                    .font(DemoType.hint)
                    .foregroundColor(tint)
                    .lineLimit(1)
            }
        }
    }

    private var glyph: String? {
        switch delta {
        case .up: return "arrowtriangle.up.fill"
        case .down, .improved: return "arrowtriangle.down.fill"
        case .flat: return nil
        }
    }

    private var amount: String {
        switch delta {
        case .up(let value): return value
        case .down(let value): return value
        case .improved(let value): return value
        case .flat: return ""
        }
    }

    private var tint: Color {
        switch delta {
        case .up, .improved: return palette.success
        case .down: return palette.danger
        case .flat: return palette.warning
        }
    }
}

// MARK: - Chart

enum DemoChartRange: String, CaseIterable, Hashable {
    case day
    case week
    case all

    var label: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .all: return "All"
        }
    }

    var subtitle: String {
        switch self {
        case .day: return "Draw calls per frame — last 10 frames"
        case .week: return "Draw calls per frame — last 7 days"
        case .all: return "Draw calls per frame — last 12 months"
        }
    }
}

struct DemoChartBar: Hashable {
    let index: Int
    let value: Double
    let label: String
}

/// "Render pipeline" — a chart built from views, not from `Canvas`.
///
/// `Canvas` can draw the marks but not be *hovered*: its content is one node
/// with no hit testing, and the column read this chart needs is per-bar. Views
/// keep each mark independently interactive; a single Canvas drawing cannot
/// expose the per-bar hover targets this chart needs.
struct DemoChartCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredIndex: Int?
    @State private var range: DemoChartRange = .day

    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var bars: [DemoChartBar] {
        Self.bars(interactions: model.interactionCount, range: range)
    }

    var body: some View {
        DemoCard(padding: layout.chartCardPadding) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Render pipeline")
                            .font(DemoType.cardTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(range.subtitle)
                            .font(DemoType.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DemoMetrics.s2)

                    if layout.showsChartLegend {
                        HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                            DemoStatusDot(palette.accentInk)

                            Text("Frame cost")
                                .font(DemoType.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    DemoRangePicker(range: $range)
                }
                .frame(height: DemoMetrics.s6)

                DemoChartPlot(
                    bars: bars,
                    width: layout.chartInnerWidth,
                    height: layout.chartPlotHeight,
                    hoveredIndex: $hoveredIndex
                )
                .padding(.top, layout.verticallyCompact ? DemoMetrics.s3 : DemoMetrics.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A deterministic, seed-style series so a screenshot stays stable across
    /// runs but still moves with the interaction count.
    static func bars(interactions: Int) -> [DemoChartBar] {
        bars(interactions: interactions, range: .day)
    }

    /// Each period has its own stable sample cadence and x-axis labels. The
    /// daily series deliberately remains byte-for-byte identical to the
    /// original chart, preserving every existing screenshot and parity test.
    static func bars(interactions: Int, range: DemoChartRange) -> [DemoChartBar] {
        let pattern: [Double]
        let labels: [String]

        switch range {
        case .day:
            pattern = [0.35, 0.52, 0.40, 0.68, 0.56, 0.82, 0.64, 0.94, 0.72, 0.58]
            labels = pattern.indices.map { "\($0 + 1)" }
        case .week:
            pattern = [0.41, 0.56, 0.49, 0.73, 0.64, 0.88, 0.70]
            labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        case .all:
            pattern = [0.28, 0.34, 0.39, 0.44, 0.50, 0.47, 0.58, 0.63, 0.69, 0.74, 0.81, 0.92]
            labels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        }

        return pattern.enumerated().map { index, base in
            let phase = (Double(index) + Double(interactions) * 0.13).truncatingRemainder(dividingBy: 1)
            let value = min(1, max(0.10, base + phase * 0.10)) * 40
            return DemoChartBar(index: index, value: value, label: labels[index])
        }
    }
}

struct DemoRangePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var range: DemoChartRange

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(DemoChartRange.allCases, id: \.self) { option in
                DemoRangeSegment(option: option, isSelected: option == range) {
                    range = option
                }
            }
        }
        .padding(2)
        .background(palette.surface2)
        .cornerRadius(DemoMetrics.radiusMD)
    }
}

struct DemoRangeSegment: View {
    @Environment(\.colorScheme) private var colorScheme

    let option: DemoChartRange
    let isSelected: Bool
    let perform: @MainActor @Sendable () -> Void

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: perform) {
            Text(option.label)
                .font(DemoType.captionStrong)
                .foregroundStyle(isSelected ? .primary : .tertiary)
                .lineLimit(1)
                .padding(.horizontal, DemoMetrics.s2)
                .frame(height: DemoMetrics.s5)
                .background(isSelected ? palette.surface3 : Color.clear)
                .cornerRadius(DemoMetrics.radiusSM)
        }
        .buttonStyle(.plain)
    }
}

/// The plot: a left gutter of y labels, four gridlines behind the bars, a
/// baseline visibly stronger than a gridline, and x labels under the marks.
/// The card is the plot's background — there is no tint box inside it.
struct DemoChartPlot: View {
    @Environment(\.colorScheme) private var colorScheme

    let bars: [DemoChartBar]
    let width: CGFloat
    let height: CGFloat
    @Binding var hoveredIndex: Int?

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private static let gutter: CGFloat = 40
    private static let labelGap: CGFloat = 8
    private static let minimumBarGap: CGFloat = 8
    private static let bottomStrip: CGFloat = 20
    /// A clear strip above the axis maximum, for the value on the tallest
    /// mark. Without it the label had nowhere to go but *inside* the plot,
    /// and the 100% gridline ran straight through the digits.
    private static let valueStrip: CGFloat = DemoMetrics.s5
    /// The `axis` role's line box. Half of it is what the y-label column is
    /// lifted by, so a label sits *on* its gridline rather than hanging under
    /// it — including the 0, which belongs on the baseline.
    private static let axisLabelHeight: CGFloat = 12

    private var plotWidth: CGFloat { max(80, width - Self.gutter) }

    /// The axis maximum, rounded up so that *every* gridline is a number a
    /// reader recognises: the quarter step is a nice 1 / 2 / 5 x 10^n and the
    /// maximum is four of them. Rounding only the top of the axis is what
    /// produces the "50 / 38 / 25 / 13" ladder, where three of the four
    /// labels are noise.
    private var axisMax: Double {
        let peak = bars.map(\.value).max() ?? 1
        guard peak > 0 else { return 4 }
        let quarter = peak / 4
        var step = 1.0
        while step * 10 <= quarter { step *= 10 }
        let candidates = [step, step * 2, step * 5, step * 10]
        let niceQuarter = candidates.first { $0 >= quarter } ?? quarter
        return niceQuarter * 4
    }

    /// Marks span the plot.
    ///
    /// The spec's fixed `clamp(available / n, 12, 40)` with a fixed 8pt gap
    /// centres the group when it is narrower than the plot, and at 1280 that
    /// left ~100pt of empty plot on each side; at 1720, where the content
    /// pane is 1238 wide, it left 324 — a chart that reads as one that failed
    /// to load the rest of its data, which is the exact failure the centring
    /// rule was written to avoid. So the ceiling scales with the plot instead
    /// of being a constant, and whatever is left over after that goes into
    /// the gap rather than into two end margins.
    private var barWidth: CGFloat {
        let count = CGFloat(max(1, bars.count))
        let available = plotWidth - Self.minimumBarGap * (count - 1)
        let ceiling = max(40, plotWidth / 14)
        return min(ceiling, max(12, available / count))
    }

    /// The leftover, spread between the marks — but never past three quarters
    /// of a bar, past which a bar chart starts reading as a lollipop chart.
    private var barGap: CGFloat {
        let count = CGFloat(max(1, bars.count))
        guard count > 1 else { return Self.minimumBarGap }
        let leftover = plotWidth - barWidth * count
        return min(barWidth * 0.75, max(Self.minimumBarGap, leftover / (count - 1)))
    }

    private var showsEveryLabel: Bool { bars.count <= 10 && barWidth >= 24 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The gutter starts where the plot does, under the value strip:
            // a y label has to sit on its own gridline.
            DemoChartAxisLabels(axisMax: axisMax, height: height)
                .frame(width: Self.gutter - Self.labelGap, alignment: .trailing)
                .padding(.top, Self.valueStrip - Self.axisLabelHeight / 2)

            Color.clear.frame(width: Self.labelGap, height: 1)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    DemoChartGridlines(color: palette.strokeSubtle, width: plotWidth, height: height)
                        .frame(width: plotWidth, height: height, alignment: .bottom)

                    DemoChartBars(
                        bars: bars,
                        axisMax: axisMax,
                        barWidth: barWidth,
                        gap: barGap,
                        height: height,
                        valueStrip: Self.valueStrip,
                        hoveredIndex: $hoveredIndex
                    )
                    .frame(width: plotWidth, height: height + Self.valueStrip, alignment: .bottom)
                }
                .frame(width: plotWidth, height: height + Self.valueStrip, alignment: .bottomLeading)

                // The baseline is a *structural* hairline, and it reaches back
                // under the y-label gutter: a chart stands on one line.
                DemoRule(palette.strokeStrong, length: plotWidth)

                DemoChartXLabels(
                    bars: bars,
                    barWidth: barWidth,
                    gap: barGap,
                    showsEveryLabel: showsEveryLabel,
                    hoveredIndex: hoveredIndex
                )
                .frame(width: plotWidth, height: Self.bottomStrip, alignment: .top)
            }
        }
        .frame(width: width, height: height + Self.valueStrip + Self.bottomStrip + 1, alignment: .topLeading)
    }
}

struct DemoChartAxisLabels: View {
    let axisMax: Double
    let height: CGFloat

    /// Each label's own box is pinned to the line box first and *then* placed
    /// at the top of its row band. Stating only the row height stretched the
    /// label to the full 37pt band, which centres its ink 18pt below the
    /// gridline it names — so the column was lifted by half a line box and
    /// the labels still hung under their lines.
    var body: some View {
        let rowHeight = height / 4
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(ticks, id: \.self) { tick in
                Text(tick)
                    .font(DemoType.axis)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(height: labelHeight, alignment: .top)
                    .frame(height: rowHeight, alignment: .top)
            }

            Text("0")
                .font(DemoType.axis)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(height: labelHeight, alignment: .top)
        }
        .frame(height: height + labelHeight, alignment: .top)
    }

    /// The `axis` role's line box, matched to `DemoChartPlot.axisLabelHeight`.
    private var labelHeight: CGFloat { 12 }

    private var ticks: [String] {
        [1.0, 0.75, 0.5, 0.25].map { fraction in
            "\(Int((axisMax * fraction).rounded()))"
        }
    }
}

struct DemoChartGridlines: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let rowHeight = height / 4
        return VStack(alignment: .leading, spacing: 0) {
            ForEach([0, 1, 2, 3], id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    DemoRule(color, length: width)

                    Spacer(minLength: 0)
                }
                .frame(width: width, height: rowHeight)
            }
        }
        .allowsHitTesting(false)
    }
}

struct DemoChartBars: View {
    @Environment(\.colorScheme) private var colorScheme

    let bars: [DemoChartBar]
    let axisMax: Double
    let barWidth: CGFloat
    let gap: CGFloat
    let height: CGFloat
    let valueStrip: CGFloat
    @Binding var hoveredIndex: Int?

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var peakIndex: Int {
        bars.max { $0.value < $1.value }?.index ?? 0
    }

    /// No spacers. A `Spacer` at each end of a stack that carries a spacing
    /// also takes a *gap* at each end, so the series came out inset by one
    /// full gap on both sides however the gap was computed. Whatever the gap
    /// cannot absorb is centred by the frame this sits in instead.
    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(bars, id: \.index) { bar in
                DemoChartBarMark(
                    bar: bar,
                    axisMax: axisMax,
                    width: barWidth,
                    height: height,
                    valueStrip: valueStrip,
                    isPeak: bar.index == peakIndex,
                    hoveredIndex: $hoveredIndex
                )
            }
        }
    }
}

struct DemoChartBarMark: View {
    @Environment(\.colorScheme) private var colorScheme

    let bar: DemoChartBar
    let axisMax: Double
    let width: CGFloat
    let height: CGFloat
    let valueStrip: CGFloat
    let isPeak: Bool
    @Binding var hoveredIndex: Int?

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var isHovered: Bool { hoveredIndex == bar.index }

    private var emphasised: Bool { isHovered || (hoveredIndex == nil && isPeak) }

    private var fill: Color {
        if emphasised { return palette.accentInk }
        if hoveredIndex != nil { return palette.accentInk.opacity(0.30) }
        return palette.accentInk.opacity(0.55)
    }

    var body: some View {
        let barHeight = max(2, height * CGFloat(min(1, bar.value / max(axisMax, 0.001))))
        // The hovered column washes to the top of the *plot*, not to the top
        // of the value strip: the strip is clear space above the axis
        // maximum, and a wash reaching into it would read as a bar that
        // overshot its own scale.
        return ZStack(alignment: .bottom) {
            Color.clear
                .frame(width: width, height: height)
                .background(isHovered ? palette.accentWash : Color.clear)

            VStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)

                if emphasised {
                    Text("\(Int(bar.value.rounded()))")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.bottom, DemoMetrics.s1 + 2)
                }

                UnevenRoundedRectangle(
                    topLeadingRadius: DemoMetrics.radiusXS,
                    topTrailingRadius: DemoMetrics.radiusXS
                )
                .fill(fill)
                .frame(width: width, height: barHeight)
            }
            .frame(width: width, height: height + valueStrip, alignment: .bottom)
        }
        .frame(width: width, height: height + valueStrip, alignment: .bottom)
        .onHover { hovering in
            if hovering {
                hoveredIndex = bar.index
            } else if hoveredIndex == bar.index {
                hoveredIndex = nil
            }
        }
    }
}

struct DemoChartXLabels: View {
    let bars: [DemoChartBar]
    let barWidth: CGFloat
    let gap: CGFloat
    let showsEveryLabel: Bool
    let hoveredIndex: Int?

    /// Exactly the bars' own stack, spacer for spacer: an x label that does
    /// not share the marks' geometry is an x label under the wrong mark.
    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(bars, id: \.index) { bar in
                Text(showsEveryLabel || bar.index % 2 == 0 ? bar.label : " ")
                    .font(hoveredIndex == bar.index ? DemoType.captionStrong : DemoType.axis)
                    .foregroundStyle(hoveredIndex == bar.index ? .primary : .tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(width: barWidth, alignment: .center)
            }
        }
        .padding(.top, DemoMetrics.s1)
    }
}

// MARK: - Activity and rail

struct DemoActivityCard: View {
    @ObservedObject var model: DemoDashboardModel
    let compact: Bool

    init(model: DemoDashboardModel, compact: Bool = false) {
        self.model = model
        self.compact = compact
    }

    var body: some View {
        DemoCard(padding: compact ? DemoMetrics.s3 : DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    Text("Activity")
                        .font(DemoType.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: DemoMetrics.s2)

                    Text("\(model.recentEvents.count) recent")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.recentEvents.prefix(5).enumerated()), id: \.offset) { entry in
                        DemoActivityRow(
                            title: entry.element,
                            detail: model.selectedModule.detailLine,
                            systemImage: model.selectedModule.systemImage
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DemoActivityRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(DemoType.bodyStrong)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: DemoMetrics.s3)

            Text(detail)
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .frame(height: DemoMetrics.listRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The rail's first group: two cards, not two cards inside a panel. The third
/// nesting level is what generates card soup.
struct DemoDetailTrackSection: View {
    @ObservedObject var model: DemoDashboardModel
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            // The same 12pt leading inset the sidebar's eyebrows take. The
            // two are the same kind of column, and an eyebrow that starts
            // 12pt further in on one side of the window than the other reads
            // as a mistake even when nobody can say which side is wrong.
            DemoEyebrow("Detail track")
                .padding(.leading, DemoMetrics.s3)

            VStack(alignment: .leading, spacing: DemoMetrics.s2 + 2) {
                ForEach(model.selectedModule.cards, id: \.title) { card in
                    DemoInfoCard(card: card)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct DemoInfoCard: View {
    let card: DemoTrackCard

    var body: some View {
        DemoCard(padding: DemoMetrics.s3 + 2) {
            VStack(alignment: .leading, spacing: 0) {
                Text(card.title)
                    .font(DemoType.cardTitle)
                    .tracking(0.15)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                Text(card.summary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DemoMetrics.s1)

                Text(card.meta)
                    .font(DemoType.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .padding(.top, DemoMetrics.s1 + 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The rail's second group: flat rows, no cards. A quick action is one line.
struct DemoQuickActionsSection: View {
    @ObservedObject var model: DemoDashboardModel
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            DemoEyebrow("Quick actions")
                .padding(.leading, DemoMetrics.s3)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.selectedModule.actions, id: \.title) { action in
                    DemoQuickActionRow(action: action) {
                        model.performAction(action.eventLabel)
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct DemoQuickActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let action: DemoAction
    let perform: @MainActor @Sendable () -> Void

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: perform) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(isHovering ? .secondary : .tertiary)

                Text(action.title)
                    .font(DemoType.bodyStrong)
                    .foregroundStyle(isHovering ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: DemoMetrics.s2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, DemoMetrics.s2)
            .frame(height: DemoMetrics.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? palette.pageItemHover : Color.clear)
            .cornerRadius(DemoMetrics.radiusSM)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// The rail column. Like the sidebar: a column, not a panel.
struct DemoRightRail: View {
    @ObservedObject var model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DemoMetrics.s6) {
                DemoDetailTrackSection(model: model, width: layout.railInnerWidth)

                DemoQuickActionsSection(model: model, width: layout.railInnerWidth)
            }
            .padding(DemoMetrics.s3)
        }
    }
}

// MARK: - Layout

/// Window-level facts about the demo that the app entry point and the
/// responsive-layout tests both have to agree on.
public enum DemoWindowMetrics {
    /// The smallest window the dashboard shell is designed to hold, in
    /// logical points of *client* area.
    ///
    /// 640x480 is the classic Windows floor and it is also exactly what this
    /// shell is built down to: at 640 pt of width the dashboard is a single
    /// column (both side columns have folded into it) whose content column
    /// still clears its 420 pt floor, and at 480 pt of height the body band
    /// still clears its 280 pt floor once the tab bar and the toolbar are
    /// taken out. `DemoResponsiveLayoutTests` pins both.
    public static let minimumSize = CGSize(width: 640, height: 480)

    /// What the tab bar takes off the top before the dashboard screen sees
    /// the window. Approximate on purpose — it is used as a *budget* in the
    /// height check, so overstating it is the safe direction.
    static let tabBarAllowance: CGFloat = 72
}

struct DemoLayout {
    let size: CGSize
    var isSidebarCollapsed: Bool = false
    var isInspectorCollapsed: Bool = false

    var compact: Bool { size.width < 1180 || size.height < 760 }

    /// Width decides which columns survive; only height decides whether the
    /// surviving content should trade decorative whitespace for live data.
    var verticallyCompact: Bool { size.height < 760 }

    // MARK: Page rhythm

    /// The page margin inside the content column. The columns themselves are
    /// full-bleed: a shell separated by gutters between floating panels is
    /// what read as stacked slabs.
    var pageMargin: CGFloat {
        verticallyCompact ? DemoMetrics.s4 : (compact ? DemoMetrics.s5 : DemoMetrics.s6)
    }
    /// Group to next group.
    var sectionGap: CGFloat {
        verticallyCompact ? DemoMetrics.s4 : (compact ? DemoMetrics.s5 : DemoMetrics.s6)
    }
    /// Card to sibling card.
    var cardGap: CGFloat { DemoMetrics.s3 }

    var toolbarHeight: CGFloat { DemoMetrics.toolbarHeight }
    var sidebarWidth: CGFloat { DemoMetrics.sidebarWidth }
    var railWidth: CGFloat { DemoMetrics.railWidth }
    var hairline: CGFloat { 1 }

    var bodyHeight: CGFloat { max(280, size.height - toolbarHeight) }

    /// The narrowest the centre column is allowed to get before the shell has
    /// to give a side column up. A real floor, not a taste: below it the stat
    /// band stops holding three cards and every label starts truncating.
    var minimumContentWidth: CGFloat { 420 }

    /// Whether the window is wide enough to carry the sidebar, and whether it
    /// is wide enough to carry the detail rail as well. A column that does not
    /// fit is dropped — and its content moves into the column that is still
    /// there, which is what makes this responsive rather than merely narrower.
    var showsSidebar: Bool {
        !isSidebarCollapsed && size.width >= sidebarWidth + hairline + minimumContentWidth
    }

    var showsRail: Bool {
        !isInspectorCollapsed && showsSidebar
            && size.width >= sidebarWidth + railWidth + hairline * 2 + minimumContentWidth
    }

    var contentWidth: CGFloat {
        var available = size.width
        if showsSidebar {
            available -= sidebarWidth + hairline
        }
        if showsRail {
            available -= railWidth + hairline
        }
        return max(minimumContentWidth, available)
    }

    /// What the columns and their rules actually ask the window for. The
    /// invariant is that it never exceeds `size.width`.
    var occupiedWidth: CGFloat {
        var total = contentWidth
        if showsSidebar {
            total += sidebarWidth + hairline
        }
        if showsRail {
            total += railWidth + hairline
        }
        return total
    }

    var contentInnerWidth: CGFloat { max(360, contentWidth - pageMargin * 2) }
    var sidebarInnerWidth: CGFloat { sidebarWidth - DemoMetrics.s3 * 2 }
    var railInnerWidth: CGFloat { railWidth - DemoMetrics.s3 * 2 }

    /// A nav chip in the collapsed strip.
    var moduleChipWidth: CGFloat { 132 }

    // MARK: Content metrics

    var heroHeight: CGFloat { 172 }
    var presentationHeroHeight: CGFloat { verticallyCompact ? 148 : heroHeight }
    var heroContentPadding: CGFloat { verticallyCompact ? DemoMetrics.s4 : DemoMetrics.s6 }
    var ambienceHeight: CGFloat { 320 }
    var chartCardPadding: CGFloat { verticallyCompact ? DemoMetrics.s4 : DemoMetrics.s5 }
    var chartPlotHeight: CGFloat { verticallyCompact ? 96 : (compact ? 120 : 148) }
    /// The plot's own width: the card's interior less its 20pt padding and
    /// the 1pt ring it draws around itself.
    var chartInnerWidth: CGFloat { max(240, contentInnerWidth - chartCardPadding * 2 - 2) }
    var showsChartLegend: Bool { chartInnerWidth >= 460 }

    var statCardWidth: CGFloat {
        max(120, (contentInnerWidth - cardGap * 2) / 3)
    }

    /// Whether the three stat cards have to stack. A question about the
    /// *content column's width* and nothing else.
    var stacksMetrics: Bool { statCardWidth < 180 }

    // MARK: Toolbar

    /// The toolbar row's own width, inside the band's 16pt insets.
    var toolbarContentWidth: CGFloat { max(320, size.width - DemoMetrics.s4 * 2) }

    var wordmarkWidth: CGFloat { compact ? 90 : 110 }
    var searchWidth: CGFloat { compact ? 220 : 280 }
    var statusChipWidth: CGFloat { 96 }
    var eventsChipWidth: CGFloat { 92 }
    var modeButtonWidth: CGFloat { compact ? 120 : 132 }

    /// What the band always carries: its insets, the wordmark, and the mode
    /// button (the one control in the band that acts).
    private var toolbarFixedWidth: CGFloat {
        DemoMetrics.s4 * 2 + wordmarkWidth + modeButtonWidth
    }

    /// The row drops its secondary chrome rather than truncating it. Nothing
    /// in the old band was optional, so a 640pt window asked for 636pt of
    /// toolbar inside 604pt of band and answered with four ellipses.
    var showsToolbarStatusPills: Bool {
        size.width >= toolbarFixedWidth + statusChipWidth + eventsChipWidth + DemoMetrics.s3 * 4
    }

    var showsToolbarSearch: Bool {
        showsToolbarStatusPills
            && size.width
                >= toolbarFixedWidth + statusChipWidth + eventsChipWidth + searchWidth + DemoMetrics.s3 * 5
    }
}

// MARK: - Content

struct DemoTrackCard {
    let title: String
    let summary: String
    let meta: String
}

struct DemoAction {
    let title: String
    let caption: String
    let systemImage: String
    let eventLabel: String
}

enum DemoModule: CaseIterable, Hashable {
    case layout
    case input
    case animation
    case controls

    var label: String {
        switch self {
        case .layout: return "Layout"
        case .input: return "Input"
        case .animation: return "Animation"
        case .controls: return "Controls"
        }
    }

    var statusLabel: String { label }

    var headline: String {
        switch self {
        case .layout: return "Pure Swift layout core"
        case .input: return "Pointer and keyboard routing"
        case .animation: return "Frame-driven UI motion"
        case .controls: return "Native control gallery"
        }
    }

    var summary: String {
        switch self {
        case .layout: return "Responsive composition and panel structure"
        case .input: return "Hover, press, focus, and scroll routing"
        case .animation: return "Frame-timed state transitions and chrome"
        case .controls: return "Toggle, slider, stepper, and input rendering"
        }
    }

    var detailLine: String {
        switch self {
        case .layout: return "Stack · Scroll · Clip"
        case .input: return "Hover · Press · Focus"
        case .animation: return "Timers · State · Redraw"
        case .controls: return "Toggle · Slider · Pick"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: return "rectangle.3.group"
        case .input: return "keyboard"
        case .animation: return "sparkles"
        case .controls: return "switch.2"
        }
    }

    /// Stop 2 of the signature gradient — the *only* thing a module tints in
    /// the whole app. Stop 1 is always `DemoSignature.accentFill`, and
    /// everything else (bars, indicators, chips, buttons, meters) takes the
    /// neutral accent. That is what kills the "three clashing hues" read while
    /// keeping module identity.
    var signatureStop: Color {
        switch self {
        case .layout: return DemoSignature.layoutStop
        case .input: return DemoSignature.inputStop
        case .animation: return DemoSignature.animationStop
        case .controls: return DemoSignature.controlsStop
        }
    }

    var cards: [DemoTrackCard] {
        switch self {
        case .layout:
            return [
                DemoTrackCard(
                    title: "Stack layout", summary: "Panels stretch with priority and padding",
                    meta: "Retention-first measurement"),
                DemoTrackCard(
                    title: "Clipping", summary: "Scissor-ready rect clipping through the render frame",
                    meta: "Backend-neutral commands"),
            ]
        case .input:
            return [
                DemoTrackCard(
                    title: "Focus chain", summary: "Tab moves through focusable retained nodes",
                    meta: "Window delegate to runtime"),
                DemoTrackCard(
                    title: "Press states", summary: "Buttons drive focused, pressed, and activated colors",
                    meta: "Main-actor control lifecycle"),
            ]
        case .animation:
            return [
                DemoTrackCard(
                    title: "Tick driver", summary: "Window animation frames advance color transitions",
                    meta: "Only when active"),
                DemoTrackCard(
                    title: "Frame cache", summary: "Unchanged UI reuses the last render frame until invalidated",
                    meta: "Retention redraws"),
            ]
        case .controls:
            return [
                DemoTrackCard(
                    title: "Toggle and slider", summary: "Interactive binding-driven controls",
                    meta: "Hit-test and focus"),
                DemoTrackCard(
                    title: "Text input", summary: "TextField and TextEditor with state", meta: "Keyboard routing"),
            ]
        }
    }

    var actions: [DemoAction] {
        switch self {
        case .layout:
            return [
                DemoAction(
                    title: "Inspect Stacks", caption: "Read the container tree", systemImage: "rectangle.3.group",
                    eventLabel: "Stack inspector opened"),
                DemoAction(
                    title: "Resize Panes", caption: "Drag the split dividers", systemImage: "rectangle.split.3x1",
                    eventLabel: "Pane editor opened"),
            ]
        case .input:
            return [
                DemoAction(
                    title: "Focus Walk", caption: "Tab through controls", systemImage: "keyboard",
                    eventLabel: "Focus walk started"),
                DemoAction(
                    title: "Route Events", caption: "Trace pointer to node", systemImage: "waveform.path.ecg",
                    eventLabel: "Input trace opened"),
            ]
        case .animation:
            return [
                DemoAction(
                    title: "Play Motion", caption: "Retrigger the status cycle", systemImage: "sparkles",
                    eventLabel: "Motion loop started"),
                DemoAction(
                    title: "Inspect Ticks", caption: "Follow runtime invalidation", systemImage: "bolt.fill",
                    eventLabel: "Tick inspector opened"),
            ]
        case .controls:
            return [
                DemoAction(
                    title: "Toggle Demo", caption: "Switch states and bindings", systemImage: "switch.2",
                    eventLabel: "Toggle demo opened"),
                DemoAction(
                    title: "Input Forms", caption: "Text and picker layout", systemImage: "textformat",
                    eventLabel: "Input form opened"),
            ]
        }
    }
}

/// Top-level screens of the product-style demo, navigated through `TabView`.
public enum DemoScreen: String, CaseIterable, Hashable {
    case dashboard
    case settings
    case data
    case gallery

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .settings: return "Settings"
        case .data: return "Data"
        case .gallery: return "Gallery"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .settings: return "gearshape"
        case .data: return "doc.text"
        case .gallery: return "square.grid.2x2"
        }
    }

    /// Gallery synonyms make the new destination discoverable without
    /// stealing the established Controls-module or component-data commands.
    var commandKeywords: [String] {
        var keywords = [label, "screen", "navigate"]
        if self == .gallery {
            keywords.append(contentsOf: ["showcase", "catalog", "patterns", "examples"])
        }
        return keywords
    }
}

/// Theme choices shown by the settings screen picker.
public enum DemoThemeOption: String, CaseIterable, Hashable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

/// A runtime component row shown on the data screen.
public struct DemoComponent: Identifiable, Hashable, Sendable {
    public let id: Int
    let name: String
    let detail: String
    let version: String
    let systemImage: String
    let load: Double

    var isHealthy: Bool { load < 0.85 }
    var statusLabel: String { isHealthy ? "Healthy" : "Degraded" }
    var loadPercent: String { "\(Int((load * 100).rounded()))%" }

    /// Restarting is a real state transition: pressure falls to a healthy,
    /// deterministic baseline and the table, inspector, and status-filter
    /// results all update from the same replacement value.
    func restarted() -> DemoComponent {
        DemoComponent(
            id: id,
            name: name,
            detail: detail,
            version: version,
            systemImage: systemImage,
            load: max(0.08, min(0.35, load * 0.4))
        )
    }

    static let defaults: [DemoComponent] = defaults(for: .direct3D11)

    static func defaults(for rendererIdentity: DemoRendererIdentity) -> [DemoComponent] {
        [
            DemoComponent(
                id: 1, name: "Render host", detail: rendererIdentity.componentDescription, version: "v2.4.1",
                systemImage: "bolt.fill", load: 0.34),
            DemoComponent(
                id: 2, name: "Input router", detail: "Pointer and keyboard dispatch", version: "v1.9.0",
                systemImage: "keyboard", load: 0.12),
            DemoComponent(
                id: 3, name: "Layout engine", detail: "Retained stack measurement", version: "v3.1.2",
                systemImage: "rectangle.3.group", load: 0.48),
            DemoComponent(
                id: 4, name: "Animation ticker", detail: "Frame-driven state transitions", version: "v1.4.0",
                systemImage: "sparkles", load: 0.27),
            DemoComponent(
                id: 5, name: "Control surfaces", detail: "Buttons, toggles, and pickers", version: "v2.0.3",
                systemImage: "switch.2", load: 0.56),
            DemoComponent(
                id: 6, name: "Event log", detail: "Interaction telemetry buffer", version: "v0.9.8",
                systemImage: "waveform.path.ecg", load: 0.71),
            DemoComponent(
                id: 7, name: "Document store", detail: "Settings persistence layer", version: "v1.2.5",
                systemImage: "doc.text", load: 0.18),
            DemoComponent(
                id: 8, name: "System probe", detail: "Health and diagnostics", version: "v0.7.2",
                systemImage: "info.circle", load: 0.90),
        ]
    }
}

// MARK: - Settings screen

/// A settings pane, not a System Settings clone.
///
/// The trailing-aligned label gutter, the centred 640pt column and the 10pt
/// uppercase eyebrows floating between boxes are gone. What is here is a
/// leading-anchored column of section boxes whose rows read left to right:
/// label, then control.
struct DemoSettingsScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    @Environment(\.openWindow) private var openWindow
    @State private var isImporterPresented = false
    @State private var isResetConfirmationPresented = false

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            settingsContent(availableWidth: proxy.size.width)
        }
        // Resolve the page tone with the screen's own inherited appearance,
        // before GeometryReader defers its content construction. Reading the
        // environment from that deferred closure can otherwise paint a dark
        // page underneath correctly light-resolved settings controls.
        .background(palette.base)
    }

    private func settingsContent(availableWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: DemoMetrics.s4) {
                    VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                        Text("Settings")
                            .font(DemoType.screenTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(model.settingsStatusMessage)
                            .font(DemoType.titleSub)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: DemoMetrics.s4)

                    // The page's one primary action is useful at the top of
                    // every window instead of below three scrolling groups.
                    DemoButton("Save Settings", kind: .accent, horizontalPadding: DemoMetrics.s4) {
                        model.saveSettings()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.settingsValidationMessage != nil)
                    .opacity(model.settingsValidationMessage == nil ? 1 : 0.55)
                }
                .padding(.top, DemoMetrics.s6)
                .frame(maxWidth: .infinity, alignment: .leading)

                DemoSettingsSection("Profile") {
                    VStack(alignment: .leading, spacing: 0) {
                        DemoSettingsRow(title: "Display Name", isFirst: true) {
                            TextField("Display Name", text: $model.displayName)
                                .labelsHidden()
                                .frame(width: 200)
                        }

                        DemoSettingsRow(title: "Theme") {
                            Picker("Theme", selection: $model.theme) {
                                Text("System").tag(DemoThemeOption.system)
                                Text("Light").tag(DemoThemeOption.light)
                                Text("Dark").tag(DemoThemeOption.dark)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        DemoSettingsRow(title: "Items Per Page") {
                            HStack(spacing: DemoMetrics.s1) {
                                TextField(
                                    "Items Per Page",
                                    value: $model.itemsPerPage,
                                    format: .number
                                )
                                .labelsHidden()
                                .frame(width: 44)

                                Stepper(
                                    "Items Per Page",
                                    value: $model.itemsPerPage,
                                    in: 5...30,
                                    step: 5
                                )
                                .labelsHidden()
                            }
                        }
                    }
                }

                DemoSettingsSection("Preferences") {
                    VStack(alignment: .leading, spacing: 0) {
                        DemoSettingsRow(title: "Enable Animations", isFirst: true) {
                            Toggle("Enable Animations", isOn: $model.animationsEnabled)
                                .labelsHidden()
                        }

                        DemoSettingsRow(title: "Sound Effects") {
                            Toggle("Sound Effects", isOn: $model.soundEffectsEnabled)
                                .labelsHidden()
                        }

                        // Two rows in the pane carry a description, and no
                        // more: past that the pane stops being a form and
                        // starts being a document.
                        DemoSettingsRow(
                            title: "Share Usage Data",
                            description: "Sample preference; this demo sends no telemetry"
                        ) {
                            Toggle("Share Usage Data", isOn: $model.shareUsageData)
                                .labelsHidden()
                        }

                        DemoSettingsRow(title: "Accent Color") {
                            ColorPicker("Accent Color", selection: $model.accentColor)
                                .labelsHidden()
                        }

                        DemoSettingsRow(
                            title: "Font Scale",
                            description: "Scales every label in the demo shell"
                        ) {
                            HStack(spacing: DemoMetrics.s2) {
                                Slider(value: $model.fontScale, in: 0.8...1.4) {
                                    Text("Font Scale")
                                }
                                .labelsHidden()
                                .frame(width: 200)

                                Text(scaleLabel)
                                    .font(DemoType.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(1)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                    }
                }

                DemoSettingsSection("Resources") {
                    VStack(alignment: .leading, spacing: 0) {
                        DemoSettingsRow(title: "Storage Used", isFirst: true) {
                            DemoSettingsMeter(value: model.storageUsed)
                        }

                        DemoSettingsRow(title: "Sync Progress") {
                            DemoSettingsMeter(value: model.syncProgress)
                        }

                        DemoSettingsRow(title: "Sync Now") {
                            DemoButton("Sync") {
                                model.runSync()
                            }
                        }
                    }
                }

                // Secondary actions stay in their own quiet, neutral group;
                // the only filled primary action already lives in the header.
                Text("Actions")
                    .font(DemoType.section)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.top, DemoMetrics.s4)
                    .padding(.bottom, DemoMetrics.s2)

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoButton("Open Second Window") {
                        openWindow(id: "main-dashboard")
                    }

                    DemoButton("Import File…") {
                        isImporterPresented = true
                    }

                    // A neutral chassis with a danger label. A filled red
                    // button in a settings list is a threat, not an option.
                    DemoButton("Reset To Defaults", labelColor: palette.danger) {
                        isResetConfirmationPresented = true
                    }

                    Spacer(minLength: 0)
                }

                Text("Changes apply immediately")
                    .font(DemoType.caption)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .padding(.top, DemoMetrics.s4)
                    .padding(.bottom, DemoMetrics.s6)
            }
            .frame(
                width: min(
                    DemoMetrics.settingsColumnWidth,
                    max(0, availableWidth - DemoMetrics.s6 * 2)
                ),
                alignment: .leading
            )
            .padding(.horizontal, DemoMetrics.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image, .plainText]
        ) { result in
            if case .success(let url) = result {
                model.noteImportedFile(url)
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset To Defaults", role: .destructive) {
                model.resetSettings()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, appearance, and preferences will return to their defaults.")
        }
    }

    private var scaleLabel: String {
        "\(Int((model.fontScale * 100).rounded()))%"
    }
}

/// A settings section: a heading attached to the group under it — 24 above,
/// 8 below — and a card holding the rows.
struct DemoSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DemoType.section)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.top, DemoMetrics.s4)
                .padding(.bottom, DemoMetrics.s2)

            // The caller supplies the row stack. Re-wrapping a
            // `@ViewBuilder` result in a stack here would hand the card one
            // opaque view holding N rows, and a view like that is laid out
            // absolutely — which drew every row of a section on top of the
            // first one.
            DemoCard(
                padding: EdgeInsets(top: 0, leading: DemoMetrics.s4, bottom: 0, trailing: DemoMetrics.s4)
            ) {
                content
            }
        }
    }
}

/// A settings row: leading label, trailing control. 36 tall, or 52 when it
/// carries a description.
///
/// No icon column. The spec makes one optional per group, and the vector
/// symbol set this stack ships covers navigation and status rather than
/// settings nouns — six rows of the fallback glyph is worse than no column at
/// all. (Recorded as a divergence in docs/MacOSDesignParity.md.)
struct DemoSettingsRow<Control: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let description: String?
    let isFirst: Bool
    let control: Control

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    init(
        title: String,
        description: String? = nil,
        isFirst: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.isFirst = isFirst
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isFirst {
                DemoRule(palette.strokeSubtle)
            }

            HStack(alignment: .center, spacing: DemoMetrics.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DemoType.bodyStrong)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    if let description {
                        Text(description)
                            .font(DemoType.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DemoMetrics.s4)

                control
            }
            .padding(.vertical, DemoMetrics.s1)
            .frame(
                minHeight: description == nil ? DemoMetrics.listRowHeight : 52,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DemoSettingsMeter: View {
    let value: Double

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            DemoMeter(value: value, width: 200)

            Text("\(Int((value * 100).rounded()))%")
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Data screen

/// A table, not a list of rows in a card: a header band, four labelled
/// columns, a load meter, and a footer inspector on the bar material.
struct DemoDataScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            let metrics = DemoTableMetrics(width: proxy.size.width)

            VStack(alignment: .leading, spacing: 0) {
                DemoDataHeader(model: model, metrics: metrics)

                DemoRule(palette.strokeStrong, length: proxy.size.width)

                DemoTableHeaderRow(model: model, metrics: metrics)

                DemoRule(palette.stroke, length: proxy.size.width)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.displayedComponents.isEmpty {
                            DemoComponentEmptyState(model: model)
                                .frame(width: proxy.size.width, alignment: .center)
                        } else {
                            ForEach(model.displayedComponents, id: \.id) { component in
                                DemoComponentRow(
                                    component: component,
                                    metrics: metrics,
                                    isSelected: model.selectedComponentID == component.id
                                ) {
                                    model.selectComponent(component)
                                }
                                .onMoveCommand { direction in
                                    switch direction {
                                    case .up:
                                        model.selectAdjacentComponent(offset: -1)
                                    case .down:
                                        model.selectAdjacentComponent(offset: 1)
                                    default:
                                        break
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.surface0)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    model.noteDroppedItems(count: providers.count)
                    return true
                }

                if model.componentPageCount > 1 {
                    DemoRule(palette.strokeSubtle, length: proxy.size.width)

                    DemoComponentPagination(model: model)
                        .frame(width: proxy.size.width, height: 48, alignment: .leading)
                }

                DemoRule(palette.strokeStrong, length: proxy.size.width)

                DemoComponentInspector(model: model, metrics: metrics)
                    .frame(width: proxy.size.width, height: DemoMetrics.footerHeight, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(palette.base)
        }
    }
}

/// Column geometry, shared by the header row and every data row so a table of
/// eight rows has one right margin rather than eight.
struct DemoTableMetrics {
    let width: CGFloat

    /// The table is full bleed — a selected row is a band across the window,
    /// which is what makes it read as a table rather than as a card that lost
    /// its border — and its *content* is inset by the page margin, not by a
    /// separate 16. The screen title above it and the first column under it
    /// have to start on the same vertical line; at 24 and 16 they were 8pt
    /// apart, which reads as a broken left edge no matter which one is right.
    static let inset: CGFloat = DemoMetrics.s6
    static let columnGap: CGFloat = DemoMetrics.s4
    static let versionWidth: CGFloat = 80
    static let loadWidth: CGFloat = 140
    static let statusWidth: CGFloat = 100

    var showsComponentCount: Bool { width >= 740 }
    var filterFieldWidth: CGFloat { width < 740 ? 180 : 240 }
    var showsInspectorLoadMeter: Bool { width >= 820 }

    var nameWidth: CGFloat {
        let fixed =
            Self.inset * 2 + Self.versionWidth + Self.loadWidth + Self.statusWidth
            + Self.columnGap * 3
        return max(140, width - fixed)
    }
}

struct DemoDataHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let metrics: DemoTableMetrics

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s3) {
            Text("Components")
                .font(DemoType.screenTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if metrics.showsComponentCount {
                Text(componentCountLabel)
                    .font(DemoType.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DemoMetrics.s4)

            DemoFilterField(model: model, width: metrics.filterFieldWidth)
        }
        .padding(.horizontal, DemoMetrics.s6)
        .frame(height: DemoMetrics.dataHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Chrome, on the same material as the toolbar band and the footer
        // inspector. Left unfilled it showed the window backdrop, which put
        // the one unpainted band in the app directly under the selector bar
        // and broke the chrome unit the two are supposed to make.
        .background(.bar)
    }

    private var componentCountLabel: String {
        let total = model.components.count
        let visible = model.displayedComponents.count
        return model.componentFilter.isEmpty && visible == total
            ? "\(total) components" : "\(visible) of \(total) components"
    }
}

struct DemoFilterField: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: DemoDashboardModel
    let width: CGFloat

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Filter components", text: $model.componentFilter)
                .font(DemoType.controlLabel)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !model.componentFilter.isEmpty {
                Button(action: { model.clearComponentFilter() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: DemoMetrics.s5, height: DemoMetrics.s5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear component filter")
            }
        }
        .padding(.horizontal, DemoMetrics.s2 + 2)
        .frame(width: width, height: DemoMetrics.controlHeight)
        .background(palette.surface2)
        .cornerRadius(DemoMetrics.radiusSM)
        .padding(1)
        .background(palette.stroke)
        .cornerRadius(DemoMetrics.radiusSM + 1)
    }
}

/// Pagination is structural, not decorative: it only takes vertical space
/// when the current filter actually spans multiple pages, preserving the
/// default eight-component screenshot and every minimum-window layout.
struct DemoComponentPagination: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s3) {
            Text(model.componentPageSummary)
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: DemoMetrics.s3)

            Text("Page \(model.componentPage + 1) of \(model.componentPageCount)")
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            DemoButton("Previous") {
                model.selectPreviousComponentPage()
            }
            .disabled(!model.hasPreviousComponentPage)
            .opacity(model.hasPreviousComponentPage ? 1 : 0.45)

            DemoButton("Next") {
                model.selectNextComponentPage()
            }
            .disabled(!model.hasNextComponentPage)
            .opacity(model.hasNextComponentPage ? 1 : 0.45)
        }
        .padding(.horizontal, DemoTableMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface0)
    }
}

/// The table's empty state keeps the same monochrome icon, type ramp, and
/// neutral button chassis as the rest of the demo while offering a real exit.
struct DemoComponentEmptyState: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        VStack(alignment: .center, spacing: DemoMetrics.s2) {
            DemoIconTile(systemImage: "magnifyingglass")

            Text("No matching components")
                .font(DemoType.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("Try another search or clear the current filter")
                .font(DemoType.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            DemoButton("Clear filter") {
                model.clearComponentFilter()
            }
            .padding(.top, DemoMetrics.s2)
        }
        .padding(.vertical, DemoMetrics.s16)
    }
}

struct DemoTableHeaderRow: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var model: DemoDashboardModel
    let metrics: DemoTableMetrics

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoTableMetrics.columnGap) {
            DemoSortableColumnHeader(model: model, column: .name, isTrailing: false)
                .frame(width: metrics.nameWidth, alignment: .leading)

            // Trailing columns are closed with a `Spacer`, not a frame
            // alignment: a `Text` carries its own alignment into the frame it
            // is given, so a trailing-aligned column header drew at its
            // leading edge and the header stopped lining up with the data
            // under it.
            DemoSortableColumnHeader(model: model, column: .version, isTrailing: true)
                .frame(width: DemoTableMetrics.versionWidth, alignment: .trailing)

            DemoSortableColumnHeader(model: model, column: .load, isTrailing: false)
                .frame(width: DemoTableMetrics.loadWidth, alignment: .leading)

            DemoSortableColumnHeader(model: model, column: .status, isTrailing: true)
                .frame(width: DemoTableMetrics.statusWidth, alignment: .trailing)
        }
        .padding(.horizontal, DemoTableMetrics.inset)
        .frame(height: DemoMetrics.tableHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The frame tone, stated rather than inherited. A column header is not
        // chrome and it is not a row; it is the strip that says where the table
        // starts, and one ramp rung under both neighbours is what lets it say
        // that without a heavier rule.
        .background(palette.base)
    }
}

/// Plain, full-width header buttons keep the resting table visually identical
/// while making every named column a real, keyboard-focusable sort control.
struct DemoSortableColumnHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    let column: DemoComponentSortColumn
    let isTrailing: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: { model.sortComponents(by: column) }) {
            HStack(alignment: .center, spacing: DemoMetrics.s1) {
                if isTrailing {
                    Spacer(minLength: 0)
                }

                DemoEyebrow(column.label)

                if model.componentSortColumn == column {
                    Image(systemName: model.componentSortDirection.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(palette.accentInk)
                }

                if !isTrailing {
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard model.componentSortColumn == column else {
            return "Sort by \(column.label)"
        }
        return "Sort by \(column.label), currently \(model.componentSortDirection.accessibilityLabel)"
    }
}

struct DemoComponentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let component: DemoComponent
    let metrics: DemoTableMetrics
    let isSelected: Bool
    let perform: @MainActor @Sendable () -> Void

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var fill: Color {
        if isSelected { return palette.accentWashStrong }
        return isHovering ? palette.pageItemHover : Color.clear
    }

    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    // The selection indicator: a 2px bar at the leading edge,
                    // not a full-bleed saturated band with white text on it.
                    (isSelected ? palette.accentInk : Color.clear)
                        .frame(width: 2, height: DemoMetrics.listRowHeight)

                    HStack(alignment: .center, spacing: DemoTableMetrics.columnGap) {
                        HStack(alignment: .center, spacing: DemoMetrics.s2) {
                            DemoRowGlyph(
                                component.systemImage,
                                accent: isSelected ? palette.accentInk : nil,
                                isHighlighted: isHovering
                            )

                            Text(component.name)
                                .font(isSelected ? DemoType.bodyStrong : DemoType.body)
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .frame(width: metrics.nameWidth, alignment: .leading)

                        HStack(alignment: .center, spacing: 0) {
                            Spacer(minLength: 0)

                            Text(component.version)
                                .font(DemoType.captionStrong)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        }
                        .frame(width: DemoTableMetrics.versionWidth, alignment: .trailing)

                        HStack(alignment: .center, spacing: DemoMetrics.s2) {
                            DemoMeter(value: component.load, width: 64)

                            Text(component.loadPercent)
                                .font(DemoType.captionStrong)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: DemoTableMetrics.loadWidth, alignment: .leading)

                        DemoStatusCell(component: component)
                            .frame(width: DemoTableMetrics.statusWidth, alignment: .trailing)
                    }
                    .padding(.horizontal, DemoTableMetrics.inset)
                }
                .frame(height: DemoMetrics.listRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill)

                DemoRule(palette.strokeSubtle)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(component.name), version \(component.version), \(component.loadPercent) load, \(component.statusLabel)"
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// The exception gets the chip; the normal case stays quiet.
struct DemoStatusCell: View {
    @Environment(\.colorScheme) private var colorScheme

    let component: DemoComponent

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    @ViewBuilder
    var body: some View {
        if component.isHealthy {
            HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                Spacer(minLength: 0)

                DemoStatusDot(palette.success)

                Text(component.statusLabel)
                    .font(DemoType.badge)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            HStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
                    DemoStatusDot(palette.warning)

                    Text(component.statusLabel)
                        .font(DemoType.badge)
                        .foregroundColor(palette.warning)
                        .lineLimit(1)
                }
                .padding(.horizontal, DemoMetrics.s2)
                .frame(height: DemoMetrics.s5)
                .background(palette.statusWash(palette.warning))
                .cornerRadius(DemoMetrics.s5 * 0.5)
            }
        }
    }
}

/// The footer inspector: a bar on the `.bar` material, closed at the top by a
/// structural hairline. Never brighter than the table it closes in dark, and
/// never darker in light.
struct DemoComponentInspector: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let metrics: DemoTableMetrics

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let component = model.selectedComponent {
                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    DemoIconTile(systemImage: component.systemImage)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(component.name)
                            .font(DemoType.cardTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(component.detail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DemoMetrics.s4)

                    if metrics.showsInspectorLoadMeter {
                        VStack(alignment: .leading, spacing: DemoMetrics.s1 + 2) {
                            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                                DemoEyebrow("Current load")

                                Spacer(minLength: DemoMetrics.s2)

                                Text(component.loadPercent)
                                    .font(DemoType.captionStrong)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 200, alignment: .leading)

                            DemoMeter(value: component.load, width: 200)
                        }

                        Spacer(minLength: DemoMetrics.s4)
                    }

                    HStack(alignment: .center, spacing: DemoMetrics.s2) {
                        DemoButton("Diagnose") {
                            model.runDiagnostics()
                        }

                        DemoButton("Restart", kind: .accent) {
                            model.restartSelectedComponent()
                        }
                    }
                }
                // The page margin, not the band's own 16: the inspector's
                // subject sits under the table's first column and the whole
                // screen — title, column header, row, subject — shares one
                // left edge.
                .padding(.horizontal, DemoTableMetrics.inset)
                .padding(.vertical, DemoMetrics.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            } else {
                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    Spacer(minLength: 0)

                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)

                    Text("Select a component to inspect")
                        .font(DemoType.body)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    DemoButton("Select first") {
                        model.selectFirstComponent()
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DemoTableMetrics.inset)
                .padding(.vertical, DemoMetrics.s3)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(.bar)
            }
        }
    }
}
