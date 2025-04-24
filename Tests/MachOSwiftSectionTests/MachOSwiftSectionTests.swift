import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
@_spi(Support) import MachOKit

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

    @Test func protocolsInFile() async throws {
        guard let protocols = machOFile.swift.protocols else {
            throw Error.notFound
        }
        for proto in protocols {
            print(proto.name(in: machOFile))
        }
    }

    @Test func nominalTypesInFile() async throws {
        guard let nominalTypes = machOFile.swift.nominalTypes else {
            throw Error.notFound
        }
        for type in nominalTypes {
//            print(type.name(in: machOFile))
            let fieldDescriptor = type.fieldDescriptor(in: machOFile)
//            print(fieldDescriptor.isBind(.mangledTypeName, in: machOFile))
            if let mangledTypeName = fieldDescriptor.mangledTypeName(in: machOFile) {
                if mangledTypeName.starts(with: "0x02"), let offset = Int(mangledTypeName[mangledTypeName.index(mangledTypeName.startIndex, offsetBy: 3)...mangledTypeName.index(mangledTypeName.startIndex, offsetBy: 5)], radix: 16) {
                    print(machOFile.resolveRebase(at: numericCast(fieldDescriptor.offset + offset + machOFile.headerStartOffset)))
                }
            }
            
//            type.fieldDescriptor(in: machOFile).records(in: machOFile).forEach { record in
//                print(record.mangledTypeName(in: machOFile), record.fieldName(in: machOFile))
//                print(record.fieldName(in: machOFile))
//            }
//            print(type.fieldDescriptor(in: machOFile).numFields)
        }
    }
    
    @Test func bind() async throws {
//        print(machOFile.fileOffset(of: 0x143b71d08))
        let bind = machOFile.resolveBind(at: 20390448)
        
        guard let info = bind?.0.info else { return }
        
        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset))
    }
    
}
