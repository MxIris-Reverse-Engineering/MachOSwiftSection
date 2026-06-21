import Foundation
import MachOKit
import MachOExtensions
import MachOFixtureSupport
@testable import MachOSwiftSection

/// Shared scaffolding for the `SwiftInterface`-level integration dumps.
///
/// Both the single-binary interface builder tests and the two-binary diffable
/// builder tests follow the same shape — index a binary (timed), render it to a
/// `String`, then either print it or write it next to the others — so that
/// common machinery (the output directory, the `prepare()` timer, the
/// console/file sinks, and the binary-identifying file name) lives here once.
protocol SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SwiftInterfaceDumpTests {
    /// The directory every dump is written under, shared so the interface and
    /// diff artifacts of the same binary co-locate for manual inspection.
    var rootDirectory: URL {
        .documentsDirectory.appending(path: "SwiftInterfaceTests")
    }

    /// Runs `prepare` and prints how long it took (unless running silently).
    /// Callers pass the whole preparation step — for the differ that means
    /// preparing *both* binaries — so the printed duration covers the real work.
    func measuringPreparation(_ prepare: () async throws -> Void) async rethrows {
        let clock = ContinuousClock()
        let duration = try await clock.measure { try await prepare() }
        #if !SILENT_TEST
        print(duration)
        #endif
    }

    /// Prints a rendered dump to the console, unless running silently.
    func printResult(_ string: String) {
        #if !SILENT_TEST
        print(string)
        #endif
    }

    /// Writes a rendered dump into `rootDirectory` under a name that identifies
    /// the binary by its build version and file name, so repeated runs overwrite
    /// in place and different binaries never collide.
    func write(
        _ string: String,
        for machO: some MachOSwiftSectionRepresentableWithCache,
        suffix: String,
        fileExtension: String = "swiftinterface"
    ) throws {
        try rootDirectory.createDirectoryIfNeeded()
        let fileName = "\(machO.loadCommands.buildVersionCommand!)-\(machO.imagePath.lastPathComponent)-\(suffix).\(fileExtension)"
        try string.write(to: rootDirectory.appending(path: fileName), atomically: true, encoding: .utf8)
    }
}

extension BuildVersionCommand: @retroactive CustomStringConvertible {
    public var description: String {
        "\(platform.stringValue)-\(sdk)"
    }
}

extension MachOKit.Platform {
    var stringValue: String {
        switch self {
        case .unknown:
            "Unknown"
        case .any:
            "Any"
        case .macOS:
            "macOS"
        case .iOS:
            "iOS"
        case .tvOS:
            "tvOS"
        case .watchOS:
            "watchOS"
        case .bridgeOS:
            "bridgeOS"
        case .macCatalyst:
            "macCatalyst"
        case .iOSSimulator:
            "iOSSimulator"
        case .tvOSSimulator:
            "tvOSSimulator"
        case .watchOSSimulator:
            "watchOSSimulator"
        case .driverKit:
            "DriverKit"
        case .visionOS:
            "visionOS"
        case .visionOSSimulator:
            "visionOSSimulator"
        case .firmware:
            "Firmware"
        case .sepOS:
            "sepOS"
        case .macOSExclaveCore:
            "macOSExclaveCore"
        case .macOSExclaveKit:
            "macOSExclaveKit"
        case .iOSExclaveCore:
            "iOSExclaveCore"
        case .iOSExclaveKit:
            "iOSExclaveKit"
        case .tvOSExclaveCore:
            "tvOSExclaveCore"
        case .tvOSExclaveKit:
            "tvOSExclaveKit"
        case .watchOSExclaveCore:
            "watchOSExclaveCore"
        case .watchOSExclaveKit:
            "watchOSExclaveKit"
        case .visionOSExclaveCore:
            "visionOSExclaveCore"
        case .visionOSExclaveKit:
            "visionOSExclaveKit"
        }
    }
}
