import Testing
import Foundation
import CwlDemangle
@_spi(Support) import MachOKit
@testable import MachOSwiftSection

enum Error: Swift.Error {
    case notFound
}

@Suite
struct FreeformSwiftSectionTests {
    

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
        try await Dump.dumpTypeContextDescriptors(in: machOFile)
    }

    // offset: 19277610 + relative: 1059358 => 20336968
    // result: 19506268
    @Test func indirectPointer() async throws {
        let typeContextDescriptor = try RelativeIndirectPointer<TypeContextDescriptor, Pointer<TypeContextDescriptor>>(relativeOffset: 1059358).resolve(from: 19277610, in: machOFile)
    }

    @Test func cwlDemangled() async throws {
//        print(_stdlib_demangleName("_$sSay_$sCRLBoardLibraryViewModelItemNode"))
//        print(try CwlDemangle.parseMangledSwiftSymbol("_$sSayCRLBoardLibraryViewModelItemNodeG_", isType: false).print())
//        print("_$sSay12MemoryLayout1BVG_".typeDemangled)
        var symbols: [SwiftSymbol] = []

        func enumerateSymbols(in symbol: SwiftSymbol, level: Int = 0) {
            symbols.append(symbol)
            print(symbol.kind, symbol.contents, level)
            for child in symbol.children {
                enumerateSymbols(in: child, level: level + 1)
            }
        }
        // _$sSaySo14CKRecordZoneIDCG
        // _$sSaySo10Foundation4UUIDVG
        // _$ss6ResultOMnySo8CRLImageCs5ErrorMp_pG
        // _$sSDySi8Freeform16CRLCRDTMapBucketCy10Foundation4UUIDV8Freeform\("CRLFreehandDrawingShapeItemBucketCRDT".count)CRLFreehandDrawingShapeItemBucketCRDTCGG
        // _$s8Freeform028CRLFloatingBoardViewControlsD18ControllerDelegate_p_pSgXw
        // _$s44CRLMacFloatingBoardControlsInternalSeparatorCSg
        // _$sSDy8Freeform18CRLBoardIdentifierV8Freeform15CRLBoardLibrary9BoardInfoCG
        do {
            let swiftSymbol = try parseMangledSwiftSymbol("_$sSDy10Foundation4UUIDVAAG")
            enumerateSymbols(in: swiftSymbol)
            print(swiftSymbol.print())
        } catch {
            print(error)
        }
//        for symbol in symbols {
//            print(symbol.kind, symbol.contents)
//        }
    }

    @Test func stdlibDemangled() async throws {
        print(_stdlib_demangleName("_$sSDy8Freeform24CRLBoardLibraryViewModel6FolderOSiGSg"))
    }
}

extension String {
    var demangled: String {
        (try? CwlDemangle.parseMangledSwiftSymbol(self, isType: false).print(using: .type)) ?? self
    }
}

extension SymbolPrintOptions {
    static var type: SymbolPrintOptions {
        Self.default.subtracting([.displayObjCModule]).union([.printForTypeName])
    }
}






