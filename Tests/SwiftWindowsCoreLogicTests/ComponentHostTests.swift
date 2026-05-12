import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@testable import SwiftWindowsUI

final class ComponentHostTests: XCTestCase {
    func testSetContentBuildsDeclarativeTreeIntoRuntimeRoot() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)

            host.setContent {
                UI.label("HEADER")
                UI.button(
                    title: "GO",
                    preferredSize: Size(width: 100, height: 40),
                    cornerRadius: 12,
                    palette: SurfacePalette(
                        idle: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                        focused: Color(red: 0.3, green: 0.4, blue: 0.5, alpha: 1),
                        pressed: Color(red: 0.4, green: 0.5, blue: 0.6, alpha: 1)
                    )
                )
            }

            XCTAssertEqual(runtime.root.children.count, 2)
            XCTAssertEqual(runtime.root.children[0].text, "HEADER")
            XCTAssertTrue(runtime.root.children[1].isFocusable)
        }
    }

    func testReloadRebuildsTreeFromUpdatedState() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var title = "FIRST"

            host.setContent {
                UI.label(title)
            }
            XCTAssertEqual(runtime.root.children.first?.text, "FIRST")

            title = "SECOND"
            host.reload()

            XCTAssertEqual(runtime.root.children.count, 1)
            XCTAssertEqual(runtime.root.children.first?.text, "SECOND")
        }
    }

    func testReloadReusesNodeWithFreshStateAndHandlers() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            var useSecondState = false
            var pointerDownEvents: [String] = []
            var contextMenuEvents: [String] = []
            var accessibilityActionEvents: [String] = []
            var dynamicDeleteEvents: [String] = []
            var dynamicMoveEvents: [String] = []
            var dynamicInsertEvents: [String] = []
            var dynamicDropEvents: [String] = []
            var dropDestinationEvents: [String] = []
            var dropConfigurationEvents: [String] = []
            var dragPayloadEvents: [String] = []
            var dragItemProviderEvents: [String] = []
            let preferenceIdentifier = ObjectIdentifier(ComponentHostTests.self)

            host.setContent {
                Component { _ in
                    let node = ViewNode()
                    let label = useSecondState ? "SECOND" : "FIRST"
                    let eventLabel = useSecondState ? "second" : "first"
                    let opacity = useSecondState ? 0.85 : 0.25
                    let zIndex = useSecondState ? 9.0 : 2.0
                    let layoutConstraints = useSecondState
                        ? LayoutConstraints(minWidth: 24, maxWidth: 72, minHeight: 12, maxHeight: 36)
                        : LayoutConstraints(minWidth: 8, maxWidth: 32, minHeight: 4, maxHeight: 16)
                    let fixedSizeAxes = useSecondState
                        ? FixedSizeAxes(horizontal: false, vertical: true)
                        : FixedSizeAxes(horizontal: true, vertical: false)
                    let transform = useSecondState
                        ? Transform2D.translation(x: 24, y: 36)
                        : Transform2D(translationX: 4, translationY: 5, scaleX: 1.25, scaleY: 0.75, rotation: 0.1)
                    let borderStrokeStyle = useSecondState
                        ? StrokeStyle(lineWidth: 5, dashPattern: [3, 1], dashOffset: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4)
                        : StrokeStyle(lineWidth: 2, dashPattern: [1, 2], dashOffset: 0.5, lineCap: .square, lineJoin: .round, miterLimit: 8)
                    let borderGradient = useSecondState
                        ? LinearGradient(
                            startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                            endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                            axis: .horizontal
                        )
                        : LinearGradient(startColor: .white, endColor: .black, axis: .vertical)
                    let clipFillStyle = RetainedClipFillStyle(
                        eoFill: useSecondState,
                        antialiased: !useSecondState
                    )
                    let scrollOffset = useSecondState ? 48.0 : 12.0
                    let submitLabel: RetainedSubmitLabel = useSecondState ? .search : .return
                    let caretOffset = useSecondState ? 4 : 1
                    let textSelectability: RetainedTextSelectability = useSecondState ? .disabled : .enabled
                    let textSelectionAffinity: RetainedTextSelectionAffinity = useSecondState ? .downstream : .upstream
                    let textInputSelection = RetainedTextSelection(
                        indices: useSecondState ? .range(1..<3) : .insertionPoint(1),
                        affinity: textSelectionAffinity
                    )
                    let textContentType = RetainedTextContentType(rawValue: useSecondState ? "password" : "username")
                    let keyboardType: RetainedKeyboardType = useSecondState ? .emailAddress : .numberPad
                    let textInputCompletion = useSecondState ? "second completion" : "first completion"
                    let textInputSuggestions = [
                        RetainedTextInputSuggestion(
                            displayText: useSecondState ? "SECOND SUGGESTION" : "FIRST SUGGESTION",
                            completion: useSecondState ? "second value" : "first value"
                        )
                    ]
                    let writingToolsBehavior: RetainedWritingToolsBehavior = useSecondState ? .disabled : .complete
                    let writingToolsAffordanceVisibility: RetainedWritingToolsAffordanceVisibility = useSecondState
                        ? .hidden
                        : .visible
                    let dictationBehavior: RetainedTextInputDictationBehavior = useSecondState
                        ? .preventDictation
                        : .inline(activation: .onSelect)
                    let isFindDisabled = useSecondState
                    let isReplaceDisabled = !useSecondState
                    let isFindNavigatorPresented = useSecondState
                    let symbolVariableValue = useSecondState ? 0.75 : 0.25
                    let imageResizingMode: RetainedImageResizingMode = useSecondState ? .tile : .stretch
                    let imageCapInsets = useSecondState
                        ? EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8)
                        : EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
                    let imageRenderingMode: RetainedImageRenderingMode = useSecondState ? .original : .template
                    let imageInterpolation: RetainedImageInterpolation = useSecondState ? .high : .low
                    let imageAntialiased = useSecondState
                    let isSubmitScopeBoundary = useSecondState
                    let accessibilityTraits: RetainedAccessibilityTraits = useSecondState
                        ? [.isSelected, .isImage]
                        : [.isButton, .isHeader]
                    let accessibilityChildBehavior: RetainedAccessibilityChildBehavior = useSecondState ? .contain : .combine
                    let accessibilitySortPriority = useSecondState ? 9.5 : 1.25
                    let toolbarPlacementTags: Set<String> = useSecondState ? ["primaryAction", "navigationBar"] : ["bottomBar"]
                    let sectionHeaderChildCount = useSecondState ? 2 : 0
                    let sectionFooterChildCount = useSecondState ? 1 : 0
                    let matchedGeometryEffect = useSecondState
                        ? RetainedMatchedGeometryEffect(
                            namespaceID: "secondNamespace",
                            elementID: "secondElement",
                            properties: 3,
                            anchor: Point(x: 1, y: 1),
                            isSource: false
                        )
                        : RetainedMatchedGeometryEffect(
                            namespaceID: "firstNamespace",
                            elementID: "firstElement",
                            properties: 1,
                            anchor: Point(x: 0, y: 0),
                            isSource: true
                        )
                    let presentationChrome = useSecondState
                        ? RetainedPresentationChrome(
                            hasBackgroundOverride: true,
                            backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                            hasCornerRadiusOverride: true,
                            cornerRadius: 18,
                            hasDragIndicatorOverride: true,
                            showsDragIndicator: false,
                            hasDetentsOverride: true,
                            detents: [.fraction(0.5), .large],
                            selectedDetent: .fraction(0.5),
                            hasBackgroundInteractionOverride: true,
                            allowsBackgroundInteraction: false,
                            hasContentInteractionOverride: true,
                            contentInteraction: .resizes,
                            hasCompactAdaptationOverride: true,
                            horizontalCompactAdaptation: .none,
                            verticalCompactAdaptation: .fullScreenCover
                        )
                        : RetainedPresentationChrome(
                            hasBackgroundOverride: true,
                            backgroundGradient: LinearGradient(
                                startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                                endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                                axis: .vertical
                            ),
                            hasCornerRadiusOverride: true,
                            cornerRadius: 8,
                            hasDragIndicatorOverride: true,
                            showsDragIndicator: true,
                            hasDetentsOverride: true,
                            detents: [.height(240), .medium],
                            selectedDetent: .height(240),
                            hasBackgroundInteractionOverride: true,
                            allowsBackgroundInteraction: true,
                            hasContentInteractionOverride: true,
                            contentInteraction: .scrolls,
                            hasCompactAdaptationOverride: true,
                            horizontalCompactAdaptation: .sheet,
                            verticalCompactAdaptation: .popover
                        )

                    node.text = label
                    node.opacity = opacity
                    node.blendMode = useSecondState ? .screen : .multiply
                    node.isCompositingGroup = useSecondState
                    node.drawingGroup = useSecondState
                        ? RetainedDrawingGroup(opaque: true, colorMode: .linear)
                        : RetainedDrawingGroup(opaque: false, colorMode: .nonLinear)
                    node.colorEffects = useSecondState
                        ? [.contrast(1.2), .luminanceToAlpha]
                        : [.brightness(0.1), .colorInvert]
                    node.viewMask = useSecondState
                        ? RetainedViewMask(horizontal: .trailing, vertical: .top)
                        : RetainedViewMask(horizontal: .center, vertical: .bottom)
                    node.listRowSeparator = useSecondState
                        ? RetainedListRowSeparator(visibility: .visible, edges: .bottom)
                        : RetainedListRowSeparator(visibility: .hidden, edges: .all)
                    node.listRowSeparatorTint = useSecondState
                        ? RetainedListSeparatorTint(color: Color(red: 0.1, green: 0.8, blue: 0.7, alpha: 1), edges: .bottom)
                        : RetainedListSeparatorTint(color: nil, edges: .top)
                    node.listSectionSeparator = useSecondState
                        ? RetainedListSectionSeparator(visibility: .visible, edges: .top)
                        : RetainedListSectionSeparator(visibility: .hidden, edges: .bottom)
                    node.listSectionSeparatorTint = useSecondState
                        ? RetainedListSeparatorTint(color: Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1), edges: .top)
                        : RetainedListSeparatorTint(color: nil, edges: .bottom)
                    node.listItemTint = useSecondState
                        ? RetainedListItemTint(color: Color(red: 0.4, green: 0.6, blue: 0.9, alpha: 1), kind: .preferred)
                        : RetainedListItemTint(color: nil, kind: .monochrome)
                    node.selectionDisabled = !useSecondState
                    node.selectionDisabledOverride = !useSecondState
                    node.deleteDisabled = !useSecondState
                    node.deleteDisabledOverride = !useSecondState
                    node.moveDisabled = useSecondState
                    node.moveDisabledOverride = useSecondState
                    node.dynamicContentIndex = useSecondState ? 6 : 3
                    node.dynamicInsertContentTypes = useSecondState ? ["public.text", "public.url"] : ["public.image"]
                    node.dynamicDropPayloadType = useSecondState ? "SecondPayload" : "FirstPayload"
                    node.dropAcceptedContentTypes = useSecondState ? ["public.text"] : ["public.png"]
                    node.dropPayloadType = useSecondState ? "SecondViewDropPayload" : "FirstViewDropPayload"
                    node.isDropDestinationEnabled = useSecondState
                    node.hasDropConfiguration = useSecondState
                    node.dragDropPreviewsFormation = useSecondState ? "stack" : "pile"
                    node.springLoadingBehavior = useSecondState ? "enabled" : "automatic"
                    node.dragPayloadType = useSecondState ? "SecondDragPayload" : "FirstDragPayload"
                    node.dragItemProviderTypeIdentifiers = useSecondState ? ["public.text"] : ["public.png"]
                    node.dragContainerItemID = useSecondState ? AnyHashable("second-id") : AnyHashable("first-id")
                    node.dragContainerNamespaceID = useSecondState ? "second-namespace" : "first-namespace"
                    node.hasDragPreview = useSecondState
                    node.horizontalScrollBounceBehavior = useSecondState ? "always" : "automatic"
                    node.verticalScrollBounceBehavior = useSecondState ? "basedOnSize" : "never"
                    node.scrollTargetBehavior = useSecondState ? "viewAligned(limitBehavior:always,anchor:nil)" : "paging"
                    node.isScrollTargetLayout = useSecondState
                    node.scrollInputBehaviors = useSecondState ? ["look(horizontal)": "enabled"] : ["handGestureShortcut": "disabled"]
                    node.scrollIndicatorsFlashOnAppear = useSecondState
                    node.scrollIndicatorsFlashTrigger = useSecondState ? "Int:2" : "Int:1"
                    node.scrollTransition = useSecondState
                        ? "asymmetric,topLeading:identity,bottomTrailing:interactive,timingCurve:easeInOut,axis:horizontal,identityEffect:identity.offset(x:0.0,y:0.0)"
                        : "symmetric,configuration:interactive,timingCurve:linear,axis:all,identityEffect:identity.opacity(0.5)"
                    node.zIndex = zIndex
                    node.layoutConstraints = layoutConstraints
                    node.fixedSizeAxes = fixedSizeAxes
                    node.transform = transform
                    node.borderGradient = borderGradient
                    node.borderStrokeStyle = borderStrokeStyle
                    node.clipFillStyle = clipFillStyle
                    node.scrollOffset = scrollOffset
                    node.textInputSubmitLabel = submitLabel
                    node.textInputCaretOffset = caretOffset
                    node.textSelectability = textSelectability
                    node.textSelectionAffinity = textSelectionAffinity
                    node.textInputSelection = textInputSelection
                    node.textContentType = textContentType
                    node.textInputKeyboardType = keyboardType
                    node.textInputCompletion = textInputCompletion
                    node.textInputSuggestions = textInputSuggestions
                    node.writingToolsBehavior = writingToolsBehavior
                    node.writingToolsAffordanceVisibility = writingToolsAffordanceVisibility
                    node.textInputDictationBehavior = dictationBehavior
                    node.isFindDisabled = isFindDisabled
                    node.isReplaceDisabled = isReplaceDisabled
                    node.isFindNavigatorPresented = isFindNavigatorPresented
                    node.symbolVariableValue = symbolVariableValue
                    node.imageResizingMode = imageResizingMode
                    node.imageCapInsets = imageCapInsets
                    node.imageRenderingMode = imageRenderingMode
                    node.imageInterpolation = imageInterpolation
                    node.imageAntialiased = imageAntialiased
                    node.isSubmitScopeBoundary = isSubmitScopeBoundary
                    node.accessibilityTraits = accessibilityTraits
                    node.accessibilityChildBehavior = accessibilityChildBehavior
                    node.accessibilitySortPriority = accessibilitySortPriority
                    node.accessibilityActions = [
                        RetainedAccessibilityAction(name: eventLabel, kind: .default) {
                            accessibilityActionEvents.append(eventLabel)
                        }
                    ]
                    node.matchedGeometryEffect = matchedGeometryEffect
                    node.presentationChrome = presentationChrome
                    node.isToolbarContainer = useSecondState
                    node.toolbarPlacementTags = toolbarPlacementTags
                    node.sectionHeaderChildCount = sectionHeaderChildCount
                    node.sectionFooterChildCount = sectionFooterChildCount
                    node.retainedPreferenceValues[preferenceIdentifier] = useSecondState ? "second-preference" : "first-preference"
                    node.retainedPreferenceTransformBoundaries = useSecondState ? [preferenceIdentifier] : []
                    node.isFocusable = useSecondState
                    node.animationStates = [
                        .opacity: AnimationState(
                            startValue: useSecondState ? 1.0 : 0.0,
                            endValue: useSecondState ? 0.55 : 0.15,
                            startTime: 10,
                            duration: 2
                        )
                    ]
                    node.onPointerDown = {
                        pointerDownEvents.append(eventLabel)
                    }
                    node.onContextMenu = { _ in
                        contextMenuEvents.append(eventLabel)
                    }
                    node.onDeleteRows = { offsets in
                        dynamicDeleteEvents.append("\(eventLabel):\(Array(offsets).map(String.init).joined(separator: ","))")
                    }
                    node.onMoveRows = { offsets, destination in
                        dynamicMoveEvents.append("\(eventLabel):\(Array(offsets).map(String.init).joined(separator: ","))->\(destination)")
                    }
                    node.onInsertRows = { offset, items in
                        dynamicInsertEvents.append("\(eventLabel):\(offset):\(items.count)")
                    }
                    node.onDropRows = { payloads, offset in
                        dynamicDropEvents.append("\(eventLabel):\(offset):\(payloads.count)")
                    }
                    node.onValidateDrop = { items, _ in
                        dropDestinationEvents.append("\(eventLabel):validate:\(items.count)")
                        return useSecondState
                    }
                    node.onDropEntered = { items, _ in
                        dropDestinationEvents.append("\(eventLabel):entered:\(items.count)")
                    }
                    node.onDropUpdated = { items, _ in
                        dropDestinationEvents.append("\(eventLabel):updated:\(items.count)")
                        return eventLabel
                    }
                    node.onDropExited = {
                        dropDestinationEvents.append("\(eventLabel):exited")
                    }
                    node.onDropProviders = { items, _ in
                        dropDestinationEvents.append("\(eventLabel):providers:\(items.count)")
                        return true
                    }
                    node.onDropPayloads = { items, _ in
                        dropDestinationEvents.append("\(eventLabel):payloads:\(items.count)")
                        return true
                    }
                    node.onMakeDropConfiguration = { items, _ in
                        dropConfigurationEvents.append("\(eventLabel):configuration:\(items.count)")
                        return eventLabel
                    }
                    node.onMakeDragPayload = {
                        dragPayloadEvents.append(eventLabel)
                        return eventLabel
                    }
                    node.onMakeDragItemProvider = {
                        dragItemProviderEvents.append(eventLabel)
                        return eventLabel
                    }
                    return node
                }
            }

            let firstNode = runtime.root.children.first
            XCTAssertNotNil(firstNode)
            XCTAssertEqual(firstNode?.text, "FIRST")
            XCTAssertEqual(firstNode?.opacity, 0.25)
            XCTAssertEqual(firstNode?.blendMode, .multiply)
            XCTAssertEqual(firstNode?.isCompositingGroup, false)
            XCTAssertEqual(firstNode?.drawingGroup, RetainedDrawingGroup(opaque: false, colorMode: .nonLinear))
            XCTAssertEqual(firstNode?.colorEffects, [.brightness(0.1), .colorInvert])
            XCTAssertEqual(firstNode?.viewMask, RetainedViewMask(horizontal: .center, vertical: .bottom))
            XCTAssertEqual(firstNode?.listRowSeparator, RetainedListRowSeparator(visibility: .hidden, edges: .all))
            XCTAssertEqual(firstNode?.listRowSeparatorTint, RetainedListSeparatorTint(color: nil, edges: .top))
            XCTAssertEqual(firstNode?.listSectionSeparator, RetainedListSectionSeparator(visibility: .hidden, edges: .bottom))
            XCTAssertEqual(firstNode?.listSectionSeparatorTint, RetainedListSeparatorTint(color: nil, edges: .bottom))
            XCTAssertEqual(firstNode?.listItemTint, RetainedListItemTint(color: nil, kind: .monochrome))
            XCTAssertEqual(firstNode?.selectionDisabled, true)
            XCTAssertEqual(firstNode?.selectionDisabledOverride, true)
            XCTAssertEqual(firstNode?.deleteDisabled, true)
            XCTAssertEqual(firstNode?.deleteDisabledOverride, true)
            XCTAssertEqual(firstNode?.moveDisabled, false)
            XCTAssertEqual(firstNode?.moveDisabledOverride, false)
            XCTAssertEqual(firstNode?.dynamicContentIndex, 3)
            XCTAssertEqual(firstNode?.dynamicInsertContentTypes, ["public.image"])
            XCTAssertEqual(firstNode?.dynamicDropPayloadType, "FirstPayload")
            XCTAssertEqual(firstNode?.dropAcceptedContentTypes, ["public.png"])
            XCTAssertEqual(firstNode?.dropPayloadType, "FirstViewDropPayload")
            XCTAssertEqual(firstNode?.isDropDestinationEnabled, false)
            XCTAssertEqual(firstNode?.hasDropConfiguration, false)
            XCTAssertEqual(firstNode?.dragDropPreviewsFormation, "pile")
            XCTAssertEqual(firstNode?.springLoadingBehavior, "automatic")
            XCTAssertEqual(firstNode?.dragPayloadType, "FirstDragPayload")
            XCTAssertEqual(firstNode?.dragItemProviderTypeIdentifiers, ["public.png"])
            XCTAssertEqual(firstNode?.dragContainerItemID, AnyHashable("first-id"))
            XCTAssertEqual(firstNode?.dragContainerNamespaceID, "first-namespace")
            XCTAssertEqual(firstNode?.hasDragPreview, false)
            XCTAssertEqual(firstNode?.horizontalScrollBounceBehavior, "automatic")
            XCTAssertEqual(firstNode?.verticalScrollBounceBehavior, "never")
            XCTAssertEqual(firstNode?.scrollTargetBehavior, "paging")
            XCTAssertEqual(firstNode?.isScrollTargetLayout, false)
            XCTAssertEqual(firstNode?.scrollInputBehaviors, ["handGestureShortcut": "disabled"])
            XCTAssertEqual(firstNode?.scrollIndicatorsFlashOnAppear, false)
            XCTAssertEqual(firstNode?.scrollIndicatorsFlashTrigger, "Int:1")
            XCTAssertEqual(
                firstNode?.scrollTransition,
                "symmetric,configuration:interactive,timingCurve:linear,axis:all,identityEffect:identity.opacity(0.5)"
            )
            XCTAssertEqual(firstNode?.zIndex, 2)
            XCTAssertEqual(firstNode?.layoutConstraints, LayoutConstraints(minWidth: 8, maxWidth: 32, minHeight: 4, maxHeight: 16))
            XCTAssertEqual(firstNode?.fixedSizeAxes, FixedSizeAxes(horizontal: true, vertical: false))
            XCTAssertEqual(firstNode?.transform, Transform2D(translationX: 4, translationY: 5, scaleX: 1.25, scaleY: 0.75, rotation: 0.1))
            XCTAssertEqual(firstNode?.borderGradient, LinearGradient(startColor: .white, endColor: .black, axis: .vertical))
            XCTAssertEqual(firstNode?.borderStrokeStyle, StrokeStyle(lineWidth: 2, dashPattern: [1, 2], dashOffset: 0.5, lineCap: .square, lineJoin: .round, miterLimit: 8))
            XCTAssertEqual(firstNode?.clipFillStyle, RetainedClipFillStyle(eoFill: false, antialiased: true))
            XCTAssertEqual(firstNode?.scrollOffset, 12)
            XCTAssertEqual(firstNode?.textInputSubmitLabel, .return)
            XCTAssertEqual(firstNode?.textInputCaretOffset, 1)
            XCTAssertEqual(firstNode?.textSelectability, .enabled)
            XCTAssertEqual(firstNode?.textSelectionAffinity, .upstream)
            XCTAssertEqual(
                firstNode?.textInputSelection,
                RetainedTextSelection(indices: .insertionPoint(1), affinity: .upstream)
            )
            XCTAssertEqual(firstNode?.textContentType, RetainedTextContentType(rawValue: "username"))
            XCTAssertEqual(firstNode?.textInputKeyboardType, .numberPad)
            XCTAssertEqual(firstNode?.textInputCompletion, "first completion")
            XCTAssertEqual(
                firstNode?.textInputSuggestions,
                [RetainedTextInputSuggestion(displayText: "FIRST SUGGESTION", completion: "first value")]
            )
            XCTAssertEqual(firstNode?.writingToolsBehavior, .complete)
            XCTAssertEqual(firstNode?.writingToolsAffordanceVisibility, .visible)
            XCTAssertEqual(firstNode?.textInputDictationBehavior, .inline(activation: .onSelect))
            XCTAssertFalse(firstNode?.isFindDisabled ?? true)
            XCTAssertTrue(firstNode?.isReplaceDisabled ?? false)
            XCTAssertFalse(firstNode?.isFindNavigatorPresented ?? true)
            XCTAssertEqual(firstNode?.symbolVariableValue, 0.25)
            XCTAssertEqual(firstNode?.imageResizingMode, .stretch)
            XCTAssertEqual(firstNode?.imageCapInsets, EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            XCTAssertEqual(firstNode?.imageRenderingMode, .template)
            XCTAssertEqual(firstNode?.imageInterpolation, .low)
            XCTAssertEqual(firstNode?.imageAntialiased, false)
            XCTAssertEqual(firstNode?.isSubmitScopeBoundary, false)
            XCTAssertEqual(firstNode?.accessibilityTraits, [.isButton, .isHeader])
            XCTAssertEqual(firstNode?.accessibilityChildBehavior, .combine)
            XCTAssertEqual(firstNode?.accessibilitySortPriority, 1.25)
            XCTAssertEqual(firstNode?.accessibilityActions.count, 1)
            XCTAssertEqual(firstNode?.accessibilityActions.first?.name, "first")
            XCTAssertEqual(firstNode?.accessibilityActions.first?.kind, .default)
            XCTAssertEqual(
                firstNode?.matchedGeometryEffect,
                RetainedMatchedGeometryEffect(
                    namespaceID: "firstNamespace",
                    elementID: "firstElement",
                    properties: 1,
                    anchor: Point(x: 0, y: 0),
                    isSource: true
                )
            )
            XCTAssertEqual(
                firstNode?.presentationChrome,
                RetainedPresentationChrome(
                    hasBackgroundOverride: true,
                    backgroundGradient: LinearGradient(
                        startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                        endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                        axis: .vertical
                    ),
                    hasCornerRadiusOverride: true,
                    cornerRadius: 8,
                    hasDragIndicatorOverride: true,
                    showsDragIndicator: true,
                    hasDetentsOverride: true,
                    detents: [.height(240), .medium],
                    selectedDetent: .height(240),
                    hasBackgroundInteractionOverride: true,
                    allowsBackgroundInteraction: true,
                    hasContentInteractionOverride: true,
                    contentInteraction: .scrolls,
                    hasCompactAdaptationOverride: true,
                    horizontalCompactAdaptation: .sheet,
                    verticalCompactAdaptation: .popover
                )
            )
            XCTAssertEqual(firstNode?.isToolbarContainer, false)
            XCTAssertEqual(firstNode?.toolbarPlacementTags, Set(["bottomBar"]))
            XCTAssertEqual(firstNode?.sectionHeaderChildCount, 0)
            XCTAssertEqual(firstNode?.sectionFooterChildCount, 0)
            XCTAssertEqual(firstNode?.retainedPreferenceValues[preferenceIdentifier] as? String, "first-preference")
            XCTAssertEqual(firstNode?.retainedPreferenceTransformBoundaries, Set<ObjectIdentifier>())
            XCTAssertEqual(firstNode?.isFocusable, false)
            XCTAssertEqual(firstNode?.animationStates[.opacity]?.endValue, 0.15)

            useSecondState = true
            host.reload()

            let reusedNode = runtime.root.children.first
            XCTAssertTrue(firstNode === reusedNode)
            XCTAssertEqual(reusedNode?.text, "SECOND")
            XCTAssertEqual(reusedNode?.opacity, 0.85)
            XCTAssertEqual(reusedNode?.blendMode, .screen)
            XCTAssertEqual(reusedNode?.isCompositingGroup, true)
            XCTAssertEqual(reusedNode?.drawingGroup, RetainedDrawingGroup(opaque: true, colorMode: .linear))
            XCTAssertEqual(reusedNode?.colorEffects, [.contrast(1.2), .luminanceToAlpha])
            XCTAssertEqual(reusedNode?.viewMask, RetainedViewMask(horizontal: .trailing, vertical: .top))
            XCTAssertEqual(reusedNode?.listRowSeparator, RetainedListRowSeparator(visibility: .visible, edges: .bottom))
            XCTAssertEqual(
                reusedNode?.listRowSeparatorTint,
                RetainedListSeparatorTint(color: Color(red: 0.1, green: 0.8, blue: 0.7, alpha: 1), edges: .bottom)
            )
            XCTAssertEqual(reusedNode?.listSectionSeparator, RetainedListSectionSeparator(visibility: .visible, edges: .top))
            XCTAssertEqual(
                reusedNode?.listSectionSeparatorTint,
                RetainedListSeparatorTint(color: Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1), edges: .top)
            )
            XCTAssertEqual(
                reusedNode?.listItemTint,
                RetainedListItemTint(color: Color(red: 0.4, green: 0.6, blue: 0.9, alpha: 1), kind: .preferred)
            )
            XCTAssertEqual(reusedNode?.selectionDisabled, false)
            XCTAssertEqual(reusedNode?.selectionDisabledOverride, false)
            XCTAssertEqual(reusedNode?.deleteDisabled, false)
            XCTAssertEqual(reusedNode?.deleteDisabledOverride, false)
            XCTAssertEqual(reusedNode?.moveDisabled, true)
            XCTAssertEqual(reusedNode?.moveDisabledOverride, true)
            XCTAssertEqual(reusedNode?.dynamicContentIndex, 6)
            XCTAssertEqual(reusedNode?.dynamicInsertContentTypes, ["public.text", "public.url"])
            XCTAssertEqual(reusedNode?.dynamicDropPayloadType, "SecondPayload")
            XCTAssertEqual(reusedNode?.dropAcceptedContentTypes, ["public.text"])
            XCTAssertEqual(reusedNode?.dropPayloadType, "SecondViewDropPayload")
            XCTAssertEqual(reusedNode?.isDropDestinationEnabled, true)
            XCTAssertEqual(reusedNode?.hasDropConfiguration, true)
            XCTAssertEqual(reusedNode?.dragDropPreviewsFormation, "stack")
            XCTAssertEqual(reusedNode?.springLoadingBehavior, "enabled")
            XCTAssertEqual(reusedNode?.dragPayloadType, "SecondDragPayload")
            XCTAssertEqual(reusedNode?.dragItemProviderTypeIdentifiers, ["public.text"])
            XCTAssertEqual(reusedNode?.dragContainerItemID, AnyHashable("second-id"))
            XCTAssertEqual(reusedNode?.dragContainerNamespaceID, "second-namespace")
            XCTAssertEqual(reusedNode?.hasDragPreview, true)
            XCTAssertEqual(reusedNode?.horizontalScrollBounceBehavior, "always")
            XCTAssertEqual(reusedNode?.verticalScrollBounceBehavior, "basedOnSize")
            XCTAssertEqual(reusedNode?.scrollTargetBehavior, "viewAligned(limitBehavior:always,anchor:nil)")
            XCTAssertEqual(reusedNode?.isScrollTargetLayout, true)
            XCTAssertEqual(reusedNode?.scrollInputBehaviors, ["look(horizontal)": "enabled"])
            XCTAssertEqual(reusedNode?.scrollIndicatorsFlashOnAppear, true)
            XCTAssertEqual(reusedNode?.scrollIndicatorsFlashTrigger, "Int:2")
            XCTAssertEqual(
                reusedNode?.scrollTransition,
                "asymmetric,topLeading:identity,bottomTrailing:interactive,timingCurve:easeInOut,axis:horizontal,identityEffect:identity.offset(x:0.0,y:0.0)"
            )
            XCTAssertEqual(reusedNode?.zIndex, 9)
            XCTAssertEqual(reusedNode?.layoutConstraints, LayoutConstraints(minWidth: 24, maxWidth: 72, minHeight: 12, maxHeight: 36))
            XCTAssertEqual(reusedNode?.fixedSizeAxes, FixedSizeAxes(horizontal: false, vertical: true))
            XCTAssertEqual(reusedNode?.transform, Transform2D.translation(x: 24, y: 36))
            XCTAssertEqual(
                reusedNode?.borderGradient,
                LinearGradient(
                    startColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                    endColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                    axis: .horizontal
                )
            )
            XCTAssertEqual(reusedNode?.borderStrokeStyle, StrokeStyle(lineWidth: 5, dashPattern: [3, 1], dashOffset: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4))
            XCTAssertEqual(reusedNode?.clipFillStyle, RetainedClipFillStyle(eoFill: true, antialiased: false))
            XCTAssertEqual(reusedNode?.scrollOffset, 48)
            XCTAssertEqual(reusedNode?.textInputSubmitLabel, .search)
            XCTAssertEqual(reusedNode?.textInputCaretOffset, 4)
            XCTAssertEqual(reusedNode?.textSelectability, .disabled)
            XCTAssertEqual(reusedNode?.textSelectionAffinity, .downstream)
            XCTAssertEqual(
                reusedNode?.textInputSelection,
                RetainedTextSelection(indices: .range(1..<3), affinity: .downstream)
            )
            XCTAssertEqual(reusedNode?.textContentType, RetainedTextContentType(rawValue: "password"))
            XCTAssertEqual(reusedNode?.textInputKeyboardType, .emailAddress)
            XCTAssertEqual(reusedNode?.textInputCompletion, "second completion")
            XCTAssertEqual(
                reusedNode?.textInputSuggestions,
                [RetainedTextInputSuggestion(displayText: "SECOND SUGGESTION", completion: "second value")]
            )
            XCTAssertEqual(reusedNode?.writingToolsBehavior, .disabled)
            XCTAssertEqual(reusedNode?.writingToolsAffordanceVisibility, .hidden)
            XCTAssertEqual(reusedNode?.textInputDictationBehavior, .preventDictation)
            XCTAssertTrue(reusedNode?.isFindDisabled ?? false)
            XCTAssertFalse(reusedNode?.isReplaceDisabled ?? true)
            XCTAssertTrue(reusedNode?.isFindNavigatorPresented ?? false)
            XCTAssertEqual(reusedNode?.symbolVariableValue, 0.75)
            XCTAssertEqual(reusedNode?.imageResizingMode, .tile)
            XCTAssertEqual(reusedNode?.imageCapInsets, EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8))
            XCTAssertEqual(reusedNode?.imageRenderingMode, .original)
            XCTAssertEqual(reusedNode?.imageInterpolation, .high)
            XCTAssertEqual(reusedNode?.imageAntialiased, true)
            XCTAssertEqual(reusedNode?.isSubmitScopeBoundary, true)
            XCTAssertEqual(reusedNode?.accessibilityTraits, [.isSelected, .isImage])
            XCTAssertEqual(reusedNode?.accessibilityChildBehavior, .contain)
            XCTAssertEqual(reusedNode?.accessibilitySortPriority, 9.5)
            XCTAssertEqual(reusedNode?.accessibilityActions.count, 1)
            XCTAssertEqual(reusedNode?.accessibilityActions.first?.name, "second")
            XCTAssertEqual(reusedNode?.accessibilityActions.first?.kind, .default)
            XCTAssertEqual(
                reusedNode?.matchedGeometryEffect,
                RetainedMatchedGeometryEffect(
                    namespaceID: "secondNamespace",
                    elementID: "secondElement",
                    properties: 3,
                    anchor: Point(x: 1, y: 1),
                    isSource: false
                )
            )
            XCTAssertEqual(
                reusedNode?.presentationChrome,
                RetainedPresentationChrome(
                    hasBackgroundOverride: true,
                    backgroundColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
                    hasCornerRadiusOverride: true,
                    cornerRadius: 18,
                    hasDragIndicatorOverride: true,
                    showsDragIndicator: false,
                    hasDetentsOverride: true,
                    detents: [.fraction(0.5), .large],
                    selectedDetent: .fraction(0.5),
                    hasBackgroundInteractionOverride: true,
                    allowsBackgroundInteraction: false,
                    hasContentInteractionOverride: true,
                    contentInteraction: .resizes,
                    hasCompactAdaptationOverride: true,
                    horizontalCompactAdaptation: .none,
                    verticalCompactAdaptation: .fullScreenCover
                )
            )
            XCTAssertEqual(reusedNode?.isToolbarContainer, true)
            XCTAssertEqual(reusedNode?.toolbarPlacementTags, Set(["primaryAction", "navigationBar"]))
            XCTAssertEqual(reusedNode?.sectionHeaderChildCount, 2)
            XCTAssertEqual(reusedNode?.sectionFooterChildCount, 1)
            XCTAssertEqual(reusedNode?.retainedPreferenceValues[preferenceIdentifier] as? String, "second-preference")
            XCTAssertEqual(reusedNode?.retainedPreferenceTransformBoundaries, [preferenceIdentifier])
            XCTAssertEqual(reusedNode?.isFocusable, true)
            XCTAssertEqual(reusedNode?.animationStates[.opacity]?.endValue, 0.55)

            reusedNode?.onPointerDown?()
            XCTAssertEqual(pointerDownEvents, ["second"])
            reusedNode?.onContextMenu?(Point(x: 4, y: 8))
            XCTAssertEqual(contextMenuEvents, ["second"])
            reusedNode?.accessibilityActions.first?.handler()
            XCTAssertEqual(accessibilityActionEvents, ["second"])
            reusedNode?.onDeleteRows?(IndexSet(integer: 6))
            XCTAssertEqual(dynamicDeleteEvents, ["second:6"])
            reusedNode?.onMoveRows?(IndexSet(integer: 6), 1)
            XCTAssertEqual(dynamicMoveEvents, ["second:6->1"])
            reusedNode?.onInsertRows?(2, ["payload"])
            XCTAssertEqual(dynamicInsertEvents, ["second:2:1"])
            reusedNode?.onDropRows?(["payload"], 4)
            XCTAssertEqual(dynamicDropEvents, ["second:4:1"])
            XCTAssertEqual(reusedNode?.onValidateDrop?(["payload"], Point(x: 1, y: 2)), true)
            reusedNode?.onDropEntered?(["payload"], Point(x: 1, y: 2))
            XCTAssertEqual(reusedNode?.onDropUpdated?(["payload"], Point(x: 3, y: 4)) as? String, "second")
            reusedNode?.onDropExited?()
            XCTAssertEqual(reusedNode?.onDropProviders?(["payload"], Point(x: 5, y: 6)), true)
            XCTAssertEqual(reusedNode?.onDropPayloads?(["payload"], Point(x: 7, y: 8)), true)
            XCTAssertEqual(
                dropDestinationEvents,
                [
                    "second:validate:1",
                    "second:entered:1",
                    "second:updated:1",
                    "second:exited",
                    "second:providers:1",
                    "second:payloads:1"
                ]
            )
            XCTAssertEqual(reusedNode?.onMakeDropConfiguration?(["payload"], Point(x: 9, y: 10)) as? String, "second")
            XCTAssertEqual(dropConfigurationEvents, ["second:configuration:1"])
            XCTAssertEqual(reusedNode?.onMakeDragPayload?() as? String, "second")
            XCTAssertEqual(dragPayloadEvents, ["second"])
            XCTAssertEqual(reusedNode?.onMakeDragItemProvider?() as? String, "second")
            XCTAssertEqual(dragItemProviderEvents, ["second"])
        }
    }
}
