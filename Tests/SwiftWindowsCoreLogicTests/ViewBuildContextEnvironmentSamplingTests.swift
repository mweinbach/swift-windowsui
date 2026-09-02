import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewBuildContextEnvironmentSamplingTests: XCTestCase {
    func testDirectEnvironmentReadSamplesProviderOnceAndStaysLive() async {
        var reads = 0
        var source = EnvironmentValues(colorScheme: .dark)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
            environmentValuesProvider: {
                reads += 1
                return source
            })

        let first = context.environmentValues
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(first.colorScheme, .dark)
        XCTAssertTrue(first.isEnabled)

        source.colorScheme = .light
        source.isEnabled = false
        let second = context.environmentValues
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(second.colorScheme, .light)
        XCTAssertFalse(second.isEnabled)
        XCTAssertEqual(first.colorScheme, .dark)
        XCTAssertTrue(first.isEnabled)
    }

    func testEnvironmentGatePreservesShortCircuitAndProviderOrder() async {
        for environmentEnabled in [false, true] {
            for providerEnabled in [false, true] {
                var events: [String] = []
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
                    isEnabledProvider: {
                        events.append("enabled")
                        return providerEnabled
                    },
                    environmentValuesProvider: {
                        events.append("environment")
                        var values = EnvironmentValues()
                        values.isEnabled = environmentEnabled
                        return values
                    })

                let values = context.environmentValues
                XCTAssertEqual(values.isEnabled, environmentEnabled && providerEnabled)
                XCTAssertEqual(events, environmentEnabled ? ["environment", "enabled"] : ["environment"])
            }
        }
    }

    func testStatefulEnvironmentProviderCannotMixTwoSnapshots() async {
        var reads = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
            environmentValuesProvider: {
                reads += 1
                var values = EnvironmentValues(colorScheme: reads == 1 ? .dark : .light)
                values.isEnabled = reads == 1
                return values
            })

        let first = context.environmentValues
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(first.colorScheme, .dark)
        XCTAssertTrue(first.isEnabled)

        let second = context.environmentValues
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(second.colorScheme, .light)
        XCTAssertFalse(second.isEnabled)
    }

    func testEnabledProviderMutationDoesNotReplaceSampledEnvironment() async {
        var source = EnvironmentValues(colorScheme: .dark)
        var events: [String] = []
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
            isEnabledProvider: {
                events.append("enabled")
                source.colorScheme = .light
                source.isEnabled = false
                return true
            },
            environmentValuesProvider: {
                events.append("environment")
                return source
            })

        let first = context.environmentValues
        XCTAssertEqual(first.colorScheme, .dark)
        XCTAssertTrue(first.isEnabled)
        XCTAssertEqual(events, ["environment", "enabled"])

        let second = context.environmentValues
        XCTAssertEqual(second.colorScheme, .light)
        XCTAssertFalse(second.isEnabled)
        XCTAssertEqual(events, ["environment", "enabled", "environment"])
    }

    func testStandaloneEnabledReadRetainsProviderFirstShortCircuit() async {
        for environmentEnabled in [false, true] {
            for providerEnabled in [false, true] {
                var events: [String] = []
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
                    isEnabledProvider: {
                        events.append("enabled")
                        return providerEnabled
                    },
                    environmentValuesProvider: {
                        events.append("environment")
                        var values = EnvironmentValues()
                        values.isEnabled = environmentEnabled
                        return values
                    })

                XCTAssertEqual(context.isEnabled, providerEnabled && environmentEnabled)
                XCTAssertEqual(events, providerEnabled ? ["enabled", "environment"] : ["enabled"])
            }
        }
    }

    func testInheritedDisableCannotBeReenabledByLocalEnvironmentOrProvider() async {
        let base = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {})
        let disabledByProvider = base.withEnabled(false)
            .withEnvironmentValue(\.isEnabled, true).withEnabled(true)
        let disabledByEnvironment = base.withEnvironmentValue(\.isEnabled, false)
            .withEnabled(true).withEnvironmentValue(\.isEnabled, true)

        // Inherited providers may themselves read a parent environment. The
        // direct getter's single sample does not remove that composition.
        for context in [disabledByProvider, disabledByEnvironment] {
            XCTAssertFalse(context.isEnabled)
            XCTAssertFalse(context.environmentValues.isEnabled)
        }
    }

    func testSamplingKeepsDynamicTypeClampAndConditionalTintFallback() async {
        for hasTint in [false, true] {
            var events: [String] = []
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
                isEnabledProvider: {
                    events.append("enabled")
                    return true
                },
                tintProvider: {
                    events.append("tint")
                    return .blue
                },
                environmentValuesProvider: {
                    events.append("environment")
                    var values = EnvironmentValues()
                    values.dynamicTypeSize = .accessibility5
                    values.minDynamicTypeSize = .small
                    values.maxDynamicTypeSize = .large
                    values.tint = hasTint ? .green : nil
                    return values
                })

            let values = context.environmentValues
            XCTAssertEqual(values.dynamicTypeSize, .large)
            XCTAssertEqual(values.tint, hasTint ? Color.green : Color.blue)
            XCTAssertEqual(events, hasTint ? ["environment", "enabled"] : ["environment", "enabled", "tint"])
        }
    }

    func testInvocationCopiesKeepFileLiveAndAlertSnapshotWithoutEarlyFileReads() async {
        var reads = 0
        var source = EnvironmentValues(colorScheme: .dark)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
            environmentValuesProvider: {
                reads += 1
                return source
            })

        let file = context.retainedFileDialogInvocationContext()
        XCTAssertEqual(reads, 0)
        let alert = context.retainedAlertInvocationContext()
        XCTAssertEqual(reads, 1)

        source.colorScheme = .light
        source.isEnabled = false
        let fileValues = file.environmentValues
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(fileValues.colorScheme, .light)
        XCTAssertFalse(fileValues.isEnabled)
        let alertValues = alert.environmentValues
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(alertValues.colorScheme, .dark)
        XCTAssertTrue(alertValues.isEnabled)
    }

    func testInvocationCopiesDoNotRetainTheirConstructionCoordinator() async {
        let witness = EnvironmentSamplingCoordinatorWitness()
        let contexts = makeSamplingInvocationContexts(witness: witness)

        withExtendedLifetime(contexts) {
            XCTAssertNil(witness.coordinator)
            XCTAssertNil(contexts.file.stateMountCoordinator)
            XCTAssertNil(contexts.alert.stateMountCoordinator)
            XCTAssertEqual(contexts.file.environmentValues.colorScheme, .dark)
            XCTAssertEqual(contexts.alert.environmentValues.colorScheme, .dark)
        }
    }
}

@MainActor
private final class EnvironmentSamplingCoordinatorWitness {
    weak var coordinator: StateMountCoordinator?
}

@MainActor
private func makeSamplingInvocationContexts(
    witness: EnvironmentSamplingCoordinatorWitness
) -> (file: ViewBuildContext, alert: ViewBuildContext) {
    let coordinator = StateMountCoordinator(
        invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
    witness.coordinator = coordinator
    let context = ViewBuildContext(
        stateMountCoordinator: coordinator,
        canvasSizeProvider: { Size(width: 160, height: 60) }, invalidateHandler: {},
        environmentValuesProvider: { EnvironmentValues(colorScheme: .dark) })
    XCTAssertNotNil(witness.coordinator)
    return (context.retainedFileDialogInvocationContext(), context.retainedAlertInvocationContext())
}
