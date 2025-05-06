import Testing
import Foundation
import CwlDemangle
@_spi(Support) import MachOKit
@testable import MachOSwiftSection

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
            try print(proto.name(in: machOFile))
        }
    }

    @Test func typeContextDescriptorsInFile() async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machOFile)
            print("----------------------------------------")
            try print(typeContextDescriptor.flags.kind, typeContextDescriptor.name(in: machOFile))
            let records = try fieldDescriptor.records(in: machOFile)
            for record in records {

                let mangledTypeNames = try record.mangledTypeName(in: machOFile)

                print("    ", mangledTypeNames.components(separatedBy: " ").map(\.demangled).joined(separator: " "))

                try print("    ", mangledTypeNames, record.fieldName(in: machOFile) ?? "nil")
                
                print("\n")

//                mangledTypeName = mangledTypeName /* .replacingOccurrences(of: "_$s", with: "") */ .replacingOccurrences(of: "Mn", with: "").replacingOccurrences(of: "Mp", with: "")

//                print("Demangled: \(mangledTypeName.typeDemangled ?? mangledTypeName)")
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

    // offset: 19277610 + relative: 1059358 => 20336968
    // result: 19506268
    @Test func indirectPointer() async throws {
//        let typeContextDescriptor: TypeContextDescriptor = try RelativeIndirectPointer(relativeOffset: 1059358).resolve(from: 19277610, in: machOFile)
    }

    @Test func demangled() async throws {
//        print(_stdlib_demangleName("_$sSay_$sCRLBoardLibraryViewModelItemNode"))
//        print(try CwlDemangle.parseMangledSwiftSymbol("_$sSayCRLBoardLibraryViewModelItemNodeG_", isType: false).print())
//        print("_$sSay12MemoryLayout1BVG_".typeDemangled)

        print("_symbolic_______7SwiftUI9TupleViewV9MakeUnary33_DE681AB5F1A334FA14ECABDE70CB1955LLV".demangled)
    }
    
    
    @Test func test() async throws {
        try RelativeDirectPointer<String>(relativeOffset: 1111).resolve(from: 0, in: machOFile)
    }
}

extension String {
    var demangled: String {
        (try? CwlDemangle.parseMangledSwiftSymbol(self, isType: false).print()) ?? self
    }
}
