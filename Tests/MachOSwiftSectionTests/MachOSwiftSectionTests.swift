import Testing
import Foundation
@testable import MachOSwiftSection
@testable import MachOKit

@Test func example() async throws {
    
}


@Suite
struct MachOSwiftSectionTests {
    enum Error: Swift.Error {
        case notFound
    }
    let machOFile: MachOFile
    init() throws {
        let path = "/System/Applications/Freeform.app/Contents/MacOS/Freeform"
        let url = URL(fileURLWithPath: path)
        guard let file = try? MachOKit.loadFromFile(url: url) else {
            throw Error.notFound
        }
        switch file {
        case let .fat(fatFile):
            machOFile = try! fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case let .machO(machO):
            machOFile = machO
        }
    }
    
    @Test
    func protocolsInFile() async throws {
        guard let protocols = machOFile.swift.protocols else {
            throw Error.notFound
        }
        for proto in protocols {
            print(proto.name(in: machOFile))
        }
    }
}
