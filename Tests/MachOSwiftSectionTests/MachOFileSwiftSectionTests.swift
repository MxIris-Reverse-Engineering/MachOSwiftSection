import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
@_spi(Support) import MachOKit
import MachOObjCSection
import SwiftDemangle
//import CwlDemangle

@Suite
struct MachOFileSwiftSectionTests {
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
        guard let protocols = machOFile.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            print(proto.name(in: machOFile))
        }
    }

    @Test func typeContextDescriptorsInFile() async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
//            print(typeContextDescriptor.layout.context.parent)
            
            let fieldDescriptor = typeContextDescriptor.fieldDescriptor(in: machOFile)
            let records = fieldDescriptor.records(in: machOFile)
            for record in records {
                guard let mangledTypeName = machOFile.makeSymbolicMangledNameStringRef(numericCast(record.offset(of: \.mangledTypeName) + Int(record.layout.mangledTypeName))) else { continue }

                print(record.mangledTypeName(in: machOFile) as Any, Optional(mangledTypeName) as Any, record.fieldName(in: machOFile) as Any)
                
                print("Demangled: \(_stdlib_demangleName(mangledTypeName))")
                
//                let result: String = getTypeFromMangledName(mangledTypeName)
//                if result == mangledTypeName {
//                    if mangledTypeName.contains("$s") {
//                        if let s = swift_demangle(mangledTypeName) {
//                            print("Demangled: \(s)")
//                        }
//                    } else {
//                        if let s = swift_demangle("$s" + mangledTypeName) {
//                            print("Demangled: \(s)")
//                        }
//                    }
//                } else {
//                    print("Demangled: \(result)")
//                }
            }
        }
    }

    @Test func rebase() async throws {
        guard let rebase = machOFile.resolveRebase(at: 22524756) else { return }
        print(rebase)
        let bind = machOFile.resolveBind(at: rebase)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }

    @Test func bind() async throws {
//        print(machOFile.fileOffset(of: 0x143b71d08))
        let bind = machOFile.resolveBind(at: 22524756)

        guard let info = bind?.0.info else { return }

        print(machOFile.dyldChainedFixups?.symbolName(for: info.nameOffset) ?? "")
    }

    @Test func contextDescriptor() async throws {
        let offset = 22524756 + machOFile.headerStartOffset
        let contextDescriptorLayout: ContextDescriptor.Layout = machOFile.fileHandle.read(offset: numericCast(offset))
        let contextDescriptor = ContextDescriptor(offset: numericCast(offset), layout: contextDescriptorLayout)
        print(contextDescriptor.flags.kind.description)
    }

    @Test func read() async throws {
        machOFile.objc.protocols64?.forEach { proto in
            print(proto.offset)
            proto.protocolList(in: machOFile).map { list in
                print(list.offset)
                list.protocols(in: machOFile).map { protos in
                    print(proto.offset)
                    print(proto.mangledName(in: machOFile))
                }
            }
        }
//        print(machOFile.fileOffset(of: 22524756))
//        print(machOFile.headerStartOffset)
//        print(machOFile.fileHandle.readString(offset: 22524756 + numericCast(machOFile.headerStartOffset)))
//        machOFile.swift.protocols?.forEach {
//            print($0.offset)
//        }
    }
    
    @Test func demangled() async throws {
        print("SDySi9Coherence10AnyCRValueVG".demangled)
    }
}
