import Foundation
import Testing
import MachOKit
import MachOFoundation

package class XcodeMachOFileTests {
    package let machOFile: MachOFile

    package class var fileName: XcodeMachOFileName { .sharedFrameworks(.DNTDocumentationModel) }

    package class var preferredArchitecture: CPUType { .arm64 }

    package init() async throws {
        let file = try File.loadFromFile(url: Self.fileName.url)
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
