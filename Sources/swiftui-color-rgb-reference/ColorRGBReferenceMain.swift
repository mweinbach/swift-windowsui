import Foundation

@main
@MainActor
enum ColorRGBReferenceMain {
    private struct Arguments {
        let observer: String
        let runId: String
        let output: URL
    }

    private enum ReferenceError: Error {
        case invalidArguments
        case invalidFixture
    }

    static func main() {
        let arguments: Arguments
        do {
            arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("color-rgb-reference: invalid arguments\n".utf8))
            exit(64)
        }

        do {
            let fixtures = RGBConstructorCase.all
            guard fixtures.count == 25,
                Set(fixtures.map(\.id)).count == 25,
                fixtures.filter({ $0.domain == .requiredFinite }).count == 23,
                fixtures.allSatisfy({
                    $0.red.isFinite && $0.green.isFinite && $0.blue.isFinite
                        && $0.opacity.isFinite && (0...1).contains($0.opacity)
                })
            else { throw ReferenceError.invalidFixture }

            let cases = fixtures.map { fixture in
                let observations: [RGBObservation]
                #if os(Windows)
                    observations = WindowsColorRGBObservation.observe(fixture)
                #elseif os(macOS)
                    observations =
                        arguments.observer == "swiftui-resolved"
                        ? NativeColorRGBObservation.resolved(fixture)
                        : NativeColorRGBObservation.appKit(fixture)
                #else
                    observations = [.unsupported(reason: "unsupported-platform")]
                #endif
                return RGBCaseRecord(fixture, observations: observations)
            }
            let report = RGBObservationReport(runId: arguments.runId, observer: arguments.observer, cases: cases)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var bytes = try encoder.encode(report)
            bytes.append(0x0A)
            try bytes.write(to: arguments.output, options: .withoutOverwriting)
            // A complete report can contain unsupported observations. The
            // collector must inspect every row; exit zero is not conformance.
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("color-rgb-reference: collection or report write failed\n".utf8))
            exit(1)
        }
    }

    private static func parseArguments(_ arguments: [String]) throws -> Arguments {
        guard arguments.count == 6 else { throw ReferenceError.invalidArguments }
        let allowed: Set<String> = ["--observer", "--run-id", "--output"]
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            let flag = arguments[index]
            let value = arguments[index + 1]
            guard allowed.contains(flag), values[flag] == nil, !value.isEmpty,
                !value.unicodeScalars.contains(where: { $0.value == 0 })
            else { throw ReferenceError.invalidArguments }
            values[flag] = value
        }
        guard let observer = values["--observer"], let rawRunId = values["--run-id"],
            let runId = UUID(uuidString: rawRunId),
            runId.uuidString.lowercased() == rawRunId.lowercased(),
            let output = values["--output"]
        else { throw ReferenceError.invalidArguments }
        #if os(Windows)
            guard observer == "windows-retained" else { throw ReferenceError.invalidArguments }
        #elseif os(macOS)
            guard observer == "swiftui-resolved" || observer == "appkit-extended-srgb" else {
                throw ReferenceError.invalidArguments
            }
        #else
            throw ReferenceError.invalidArguments
        #endif
        return Arguments(
            observer: observer, runId: runId.uuidString.lowercased(),
            output: URL(fileURLWithPath: output).standardizedFileURL)
    }
}
