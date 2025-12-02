import Foundation
import Testing
import MachOKit
import MachOFoundation

package class MachOFileTests: @unchecked Sendable {
    package let machOFile: MachOFile

    package class var fileName: MachOFileName { .Finder }

    package class var preferredArchitecture: CPUType { .arm64 }

    @available(macOS 13.0, *)
    package init() async throws {
        let file = try loadFromFile(named: Self.fileName)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try required(fatFile.machOFiles().first(where: { $0.header.cpuType == Self.preferredArchitecture }) ?? fatFile.machOFiles().first)
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }
    }
}
