import Testing
import Foundation
@_spi(Core) @_spi(Support) @testable import MachOSwiftSection
import MachOKit
@_spi(Core) import MachOObjCSection
import SwiftDemangle
import CwlDemangle

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
            let records = try fieldDescriptor.records(in: machOFile)
            for record in records {
                var mangledTypeName = try record.mangledTypeName(in: machOFile)

                try print(Optional(mangledTypeName) as Any, record.fieldName(in: machOFile) as Any)
                
                mangledTypeName = mangledTypeName/*.replacingOccurrences(of: "_$s", with: "")*/.replacingOccurrences(of: "Mn", with: "").replacingOccurrences(of: "Mp", with: "")
                
                print("Demangled: \(mangledTypeName.typeDemangled ?? mangledTypeName)")
                
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
        let contextDescriptorLayout: ContextDescriptor.Layout = try machOFile.fileHandle.read(offset: numericCast(offset))
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

    // offset: 19277610 + relative: 1059358 => 20336968
    // result: 19506268
    @Test func indirectPointer() async throws {
//        let typeContextDescriptor: TypeContextDescriptor = try RelativeIndirectPointer(relativeOffset: 1059358).resolve(from: 19277610, in: machOFile)
//        print(try typeContextDescriptor.name(in: machOFile))
//        let objcProtocol: ObjCProtocol64 = try RelativeIndirectPointer(relativeOffset: -2124150).resolve(from: 19278726, in: machOFile)
//        print(objcProtocol.mangledName(in: machOFile))
//        print(try RelativeDirectPointer<ObjCProtocol64>(relativeOffset: -2124150).resolveAddress(from: 19278726, in: machOFile))
        // 2124132
//        print(try machOFile.fileHandle.read(offset: numericCast(19278726 - 2124150 + 4 + 2124132)) as Int32)
        try print(machOFile.makeSymbolicMangledNameStringRef(numericCast(19278726 - 2124150 + 4 + 2124132)))
//        print(try machOFile.fileHandle.readString(offset: numericCast(19278726 - 2124150 + 4 + 2124132)))
    }

    @Test func demangled() async throws {
//        print(_stdlib_demangleName("_$sSay_$sCRLBoardLibraryViewModelItemNode"))
//        print(try CwlDemangle.parseMangledSwiftSymbol("_$sSayCRLBoardLibraryViewModelItemNodeG_", isType: false).print())
//        print("_$sSay12MemoryLayout1BVG_".typeDemangled)
        
        print("_symbolic_______7SwiftUI9TupleViewV9MakeUnary33_DE681AB5F1A334FA14ECABDE70CB1955LLV".typeDemangled)
    }
}

extension ObjCProtocol64: LayoutWrapperWithOffset {
    public init(offset: Int, layout: Layout) {
        self.init(layout: layout, offset: offset)
    }
}

extension String {
    var typeDemangled: String? {
        try? CwlDemangle.parseMangledSwiftSymbol(self, isType: true).print()
    }
}
