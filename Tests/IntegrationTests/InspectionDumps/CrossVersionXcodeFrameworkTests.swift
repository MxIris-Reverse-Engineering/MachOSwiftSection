import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import FoundationToolbox
import SwiftStdlibToolbox

/// A shared framework of two installed Xcode applications, picked by
/// version — `/Applications/Xcode-<version>.app` — which also labels it on
/// the axis. A suite points at one of these; to look at another framework or
/// other Xcodes, add one.
struct XcodeFrameworkPairConfiguration: Sendable {
    let frameworkName: String
    let oldXcodeVersion: String
    let newXcodeVersion: String

    static var dvtProductsUI: Self {
        Self(frameworkName: "DVTProductsUI", oldXcodeVersion: "26.3.0", newXcodeVersion: "26.4.0")
    }
}

/// The same shared framework from two installed Xcode applications, picked
/// by version: `/Applications/Xcode-<version>.app`. The shared
/// `XcodeMachOFileName` fixture names a single Xcode, so this loads by path.
/// `configuration` names the framework and the two versions.
@TestActor
class CrossVersionXcodeFrameworkTests: Sendable {
    let oldMachOFile: MachOFile
    let newMachOFile: MachOFile
    private let axes: VersionAxes

    class var configuration: XcodeFrameworkPairConfiguration { .dvtProductsUI }

    init() async throws {
        let configuration = Self.configuration
        let frameworkName = configuration.frameworkName
        let oldMachOFile = try Self.loadSharedFramework(named: frameworkName, fromXcodeVersion: configuration.oldXcodeVersion)
        let newMachOFile = try Self.loadSharedFramework(named: frameworkName, fromXcodeVersion: configuration.newXcodeVersion)
        self.oldMachOFile = oldMachOFile
        self.newMachOFile = newMachOFile
        self.axes = VersionAxes(
            versions: [
                AxisVersion(label: configuration.oldXcodeVersion, images: [AxisImage(imageName: frameworkName, machOFile: oldMachOFile)]),
                AxisVersion(label: configuration.newXcodeVersion, images: [AxisImage(imageName: frameworkName, machOFile: newMachOFile)]),
            ],
            comparesImageGroups: false,
            availabilityPlatform: nil
        )
    }

    nonisolated func versionAxis(for language: MetadataLanguage) -> VersionAxis {
        axes.axis(for: language)
    }

    private static func loadSharedFramework(named name: String, fromXcodeVersion xcodeVersion: String) throws -> MachOFile {
        let binaryPath = "/Applications/Xcode-\(xcodeVersion).app/Contents/SharedFrameworks/\(name).framework/Versions/A/\(name)"
        return try HostSlice.machOFile(at: URL(fileURLWithPath: binaryPath))
    }
}
