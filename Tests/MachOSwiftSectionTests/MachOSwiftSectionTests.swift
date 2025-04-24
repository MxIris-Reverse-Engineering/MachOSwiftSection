import Testing
import Foundation
@testable import MachOSwiftSection
@testable import MachOKit

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
            self.machOFile = try! fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case let .machO(machO):
            self.machOFile = machO
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

    @Test
    func nominalTypesInFile() async throws {
        guard let nominalTypes = machOFile.swift.nominalTypes else {
            throw Error.notFound
        }
        for type in nominalTypes {
//            print(type.name(in: machOFile))
            print(type.fieldDescriptor(in: machOFile).mangledTypeName(in: machOFile))
//            type.fieldDescriptor(in: machOFile).records(in: machOFile).forEach { record in
//                print(record.mangledTypeName(in: machOFile), record.fieldName(in: machOFile))
//                print(record.fieldName(in: machOFile))
//            }
//            print(type.fieldDescriptor(in: machOFile).numFields)
        }
    }
}
