import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import FoundationToolbox
import SwiftStdlibToolbox

/// The same file in two simulator runtimes, and the runtime versions that
/// label them on the axis. A suite points at one of these; to look at
/// another file, add one.
struct SimulatorFilePairConfiguration: Sendable {
    let oldFileName: MachOFileName
    let newFileName: MachOFileName
    let oldVersionLabel: String
    let newVersionLabel: String

    static var swiftUICore: Self {
        Self(oldFileName: .iOS_18_5_Simulator_SwiftUICore, newFileName: .iOS_26_5_Simulator_SwiftUICore, oldVersionLabel: "18.5", newVersionLabel: "26.5")
    }

    static var swiftUI: Self {
        Self(oldFileName: .iOS_18_5_Simulator_SwiftUI, newFileName: .iOS_26_5_Simulator_SwiftUI, oldVersionLabel: "18.5", newVersionLabel: "26.5")
    }
}

/// The same file from two simulator runtimes, by fixture name — the
/// two-version counterpart of `SwiftSectionTestingSupport.MachOFileTests`,
/// which loads one. `configuration` names the pair.
@TestActor
class CrossVersionMachOFileTests: Sendable {
    let oldMachOFile: MachOFile
    let newMachOFile: MachOFile
    private let axes: VersionAxes

    class var configuration: SimulatorFilePairConfiguration { .swiftUICore }

    init() async throws {
        let configuration = Self.configuration
        let oldMachOFile = try HostSlice.machOFile(in: loadFromFile(named: configuration.oldFileName))
        let newMachOFile = try HostSlice.machOFile(in: loadFromFile(named: configuration.newFileName))
        self.oldMachOFile = oldMachOFile
        self.newMachOFile = newMachOFile
        self.axes = VersionAxes(
            versions: [
                AxisVersion(label: configuration.oldVersionLabel, images: [AxisImage(imageName: oldMachOFile.imagePath.lastPathComponent, machOFile: oldMachOFile)]),
                AxisVersion(label: configuration.newVersionLabel, images: [AxisImage(imageName: newMachOFile.imagePath.lastPathComponent, machOFile: newMachOFile)]),
            ],
            comparesImageGroups: false,
            availabilityPlatform: nil
        )
    }

    nonisolated func versionAxis(for language: MetadataLanguage) -> VersionAxis {
        axes.axis(for: language)
    }
}
