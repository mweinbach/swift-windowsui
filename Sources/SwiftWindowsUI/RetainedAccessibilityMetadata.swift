import Foundation
import SwiftWindowsCore

/// An authored value is distinct from an absent modifier, including optional nil.
package enum RetainedAccessibilityOverride<Value> {
    case inherit
    case set(Value)

    package func resolve(inheriting value: Value) -> Value {
        switch self {
        case .inherit: return value
        case .set(let explicit): return explicit
        }
    }
}

extension RetainedAccessibilityOverride: Equatable where Value: Equatable {}

/// Copied presentation metadata. This value contains no effect or disclosure authority.
package struct RetainedAccessibilitySemanticMetadata: Equatable {
    package var label: String?
    package var description: String?
    package var value: String?
    package var hint: String?
    package var identifier: String?
    package var language: String?
    package var linkedGroup: String?
    package var page: String?
    package var linkDestination: URL?

    package var isHidden: Bool
    package var ignoresInvertColors: Bool
    package var showsLargeContentViewer: Bool
    package var isQuickActionEnabled: Bool
    package var isZoomActionEnabled: Bool
    package var isScrollActionEnabled: Bool
    package var isFocusSection: Bool
    package var isImage: Bool

    package var respondsToUserInteraction: Bool?
    package var prefersSliderBehavior: Bool?
    package var requiresActivationPoint: Bool?
    package var prefersCrossFadeTransitions: Bool?
    package var showLargeContentViewer: Bool?

    package var sortPriority: Double
    package var inputLabels: [String]
    package var headingLevel: RetainedAccessibilityHeadingLevel?
    package var textualContext: RetainedAccessibilityTextualContext?
    package var directTouchOptions: RetainedAccessibilityDirectTouchOptions?
    package var quickActionStyle: AccessibilityQuickActionStyle?
    package var activationPoint: UnitPoint?
    package var textContentType: AccessibilityTextContentType?
    package var traits: RetainedAccessibilityTraits

    /// Read stored native values only; constructing this copy never publishes a mapping.
    @MainActor
    package init(node: ViewNode) {
        label = node.accessibilityLabel
        description = node.accessibilityDescription
        value = node.accessibilityValue
        hint = node.accessibilityHint
        identifier = node.accessibilityIdentifier
        language = node.accessibilityLanguage
        linkedGroup = node.accessibilityLinkedGroup
        page = node.accessibilityPage
        linkDestination = node.accessibilityLinkDestination

        isHidden = node.isAccessibilityHidden
        ignoresInvertColors = node.accessibilityIgnoresInvertColors
        showsLargeContentViewer = node.isAccessibilityShowsLargeContentViewer
        isQuickActionEnabled = node.isAccessibilityQuickActionEnabled
        isZoomActionEnabled = node.isAccessibilityZoomActionEnabled
        isScrollActionEnabled = node.isAccessibilityScrollActionEnabled
        isFocusSection = node.isAccessibilityFocusSection
        isImage = node.isAccessibilityImage

        respondsToUserInteraction = node.accessibilityRespondsToUserInteraction
        prefersSliderBehavior = node.accessibilityPrefersSliderBehavior
        requiresActivationPoint = node.accessibilityRequiresActivationPoint
        prefersCrossFadeTransitions = node.accessibilityPrefersCrossFadeTransitions
        showLargeContentViewer = node.accessibilityShowLargeContentViewer

        sortPriority = node.accessibilitySortPriority
        inputLabels = node.accessibilityInputLabels
        headingLevel = node.accessibilityHeadingLevel
        textualContext = node.accessibilityTextualContext
        directTouchOptions = node.accessibilityDirectTouchOptions
        quickActionStyle = node.accessibilityQuickActionStyle
        activationPoint = node.accessibilityActivationPoint
        textContentType = node.accessibilityTextContentType
        traits = node.accessibilityTraits
    }
}

/// Scalar intent for one declared frame. Child policies, representation and action
/// ownership remain separate from these values and their ordered trait edits.
package struct RetainedFrameAccessibilityIntent: Equatable {
    package var label: RetainedAccessibilityOverride<String?> = .inherit
    package var description: RetainedAccessibilityOverride<String?> = .inherit
    package var value: RetainedAccessibilityOverride<String?> = .inherit
    package var hint: RetainedAccessibilityOverride<String?> = .inherit
    package var identifier: RetainedAccessibilityOverride<String?> = .inherit
    package var language: RetainedAccessibilityOverride<String?> = .inherit
    package var linkedGroup: RetainedAccessibilityOverride<String?> = .inherit
    package var page: RetainedAccessibilityOverride<String?> = .inherit
    package var linkDestination: RetainedAccessibilityOverride<URL?> = .inherit

    package var isHidden: RetainedAccessibilityOverride<Bool> = .inherit
    package var ignoresInvertColors: RetainedAccessibilityOverride<Bool> = .inherit
    package var showsLargeContentViewer: RetainedAccessibilityOverride<Bool> = .inherit
    package var isQuickActionEnabled: RetainedAccessibilityOverride<Bool> = .inherit
    package var isZoomActionEnabled: RetainedAccessibilityOverride<Bool> = .inherit
    package var isScrollActionEnabled: RetainedAccessibilityOverride<Bool> = .inherit
    package var isFocusSection: RetainedAccessibilityOverride<Bool> = .inherit
    package var isImage: RetainedAccessibilityOverride<Bool> = .inherit

    package var respondsToUserInteraction: RetainedAccessibilityOverride<Bool?> = .inherit
    package var prefersSliderBehavior: RetainedAccessibilityOverride<Bool?> = .inherit
    package var requiresActivationPoint: RetainedAccessibilityOverride<Bool?> = .inherit
    package var prefersCrossFadeTransitions: RetainedAccessibilityOverride<Bool?> = .inherit
    package var showLargeContentViewer: RetainedAccessibilityOverride<Bool?> = .inherit

    package var sortPriority: RetainedAccessibilityOverride<Double> = .inherit
    package var inputLabels: RetainedAccessibilityOverride<[String]> = .inherit
    package var headingLevel: RetainedAccessibilityOverride<RetainedAccessibilityHeadingLevel?> = .inherit
    package var textualContext: RetainedAccessibilityOverride<RetainedAccessibilityTextualContext?> = .inherit
    package var directTouchOptions: RetainedAccessibilityOverride<RetainedAccessibilityDirectTouchOptions?> = .inherit
    package var quickActionStyle: RetainedAccessibilityOverride<AccessibilityQuickActionStyle?> = .inherit
    package var activationPoint: RetainedAccessibilityOverride<UnitPoint?> = .inherit
    package var textContentType: RetainedAccessibilityOverride<AccessibilityTextContentType?> = .inherit

    package private(set) var addedTraits: RetainedAccessibilityTraits = []
    package private(set) var removedTraits: RetainedAccessibilityTraits = []

    package init() {}

    /// Keep the last authored operation for each bit, including unnamed native bits.
    package mutating func addTraits(_ traits: RetainedAccessibilityTraits) {
        removedTraits.subtract(traits)
        addedTraits.formUnion(traits)
    }

    package mutating func removeTraits(_ traits: RetainedAccessibilityTraits) {
        addedTraits.subtract(traits)
        removedTraits.formUnion(traits)
    }

    /// Apply one frame after its inner content; values never write back to a node.
    package func applying(to base: RetainedAccessibilitySemanticMetadata) -> RetainedAccessibilitySemanticMetadata {
        var result = base
        result.label = label.resolve(inheriting: base.label)
        result.description = description.resolve(inheriting: base.description)
        result.value = value.resolve(inheriting: base.value)
        result.hint = hint.resolve(inheriting: base.hint)
        result.identifier = identifier.resolve(inheriting: base.identifier)
        result.language = language.resolve(inheriting: base.language)
        result.linkedGroup = linkedGroup.resolve(inheriting: base.linkedGroup)
        result.page = page.resolve(inheriting: base.page)
        result.linkDestination = linkDestination.resolve(inheriting: base.linkDestination)

        result.isHidden = isHidden.resolve(inheriting: base.isHidden)
        result.ignoresInvertColors = ignoresInvertColors.resolve(inheriting: base.ignoresInvertColors)
        result.showsLargeContentViewer = showsLargeContentViewer.resolve(inheriting: base.showsLargeContentViewer)
        result.isQuickActionEnabled = isQuickActionEnabled.resolve(inheriting: base.isQuickActionEnabled)
        result.isZoomActionEnabled = isZoomActionEnabled.resolve(inheriting: base.isZoomActionEnabled)
        result.isScrollActionEnabled = isScrollActionEnabled.resolve(inheriting: base.isScrollActionEnabled)
        result.isFocusSection = isFocusSection.resolve(inheriting: base.isFocusSection)
        result.isImage = isImage.resolve(inheriting: base.isImage)

        result.respondsToUserInteraction = respondsToUserInteraction.resolve(inheriting: base.respondsToUserInteraction)
        result.prefersSliderBehavior = prefersSliderBehavior.resolve(inheriting: base.prefersSliderBehavior)
        result.requiresActivationPoint = requiresActivationPoint.resolve(inheriting: base.requiresActivationPoint)
        result.prefersCrossFadeTransitions = prefersCrossFadeTransitions.resolve(
            inheriting: base.prefersCrossFadeTransitions)
        result.showLargeContentViewer = showLargeContentViewer.resolve(inheriting: base.showLargeContentViewer)

        result.sortPriority = sortPriority.resolve(inheriting: base.sortPriority)
        result.inputLabels = inputLabels.resolve(inheriting: base.inputLabels)
        result.headingLevel = headingLevel.resolve(inheriting: base.headingLevel)
        result.textualContext = textualContext.resolve(inheriting: base.textualContext)
        result.directTouchOptions = directTouchOptions.resolve(inheriting: base.directTouchOptions)
        result.quickActionStyle = quickActionStyle.resolve(inheriting: base.quickActionStyle)
        result.activationPoint = activationPoint.resolve(inheriting: base.activationPoint)
        result.textContentType = textContentType.resolve(inheriting: base.textContentType)
        result.traits.subtract(removedTraits)
        result.traits.formUnion(addedTraits)
        return result
    }
}
