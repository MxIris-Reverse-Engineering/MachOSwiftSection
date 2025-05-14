import Testing
import Foundation
import MachOKit
@testable import MachOSwiftSection

enum Error: Swift.Error {
    case notFound
}

@Suite
struct MachOFileSwiftSectionTests {
    let machOFile: MachOFile

    init() throws {
        let path = "/System/Applications/Freeform.app/Contents/MacOS/Freeform"
//        let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
        let url = URL(fileURLWithPath: path)
        guard let file = try? MachOKit.loadFromFile(url: url) else {
            throw Error.notFound
        }
        switch file {
        case let .fat(fatFile):
            self.machOFile = try! fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case let .machO(machO):
            self.machOFile = machO
        }
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = machOFile.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            try print(proto.name(in: machOFile))
        }
    }

    @Test func typeContextDescriptorsInFile() async throws {
        try await Dump.dumpTypeContextDescriptors(in: machOFile)
    }
}
