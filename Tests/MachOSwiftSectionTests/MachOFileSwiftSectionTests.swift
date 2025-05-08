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

    @Test func anonymousContextDescriptor() async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
            if let parent = try typeContextDescriptor.parent(in: machOFile)/*, case let .anonymous(anonymousContextDescriptor) = parent */ {
//                if case let .type(typeContextDescriptor) = parent.contextDescriptor.layout.flags.kindSpecificFlags {
//                    print(try parent.contextDescriptor.parent(in: machOFile))
//                }
//                let kind = parent.contextDescriptor.layout.flags.kind
//                if kind == .enum /*|| kind == .struct || kind == .class*/ {
                    print(try parent.contextDescriptor.parent(in: machOFile)?.name(in: machOFile))
//                }
//                print(parent.contextDescriptor.layout.flags.kind)
//                print(try anonymousContextDescriptor.mangledName(in: machOFile))
            }
        }
    }

    @Test func typeContextDescriptorsInFile() async throws {
        guard let typeContextDescriptors = machOFile.swift.typeContextDescriptors else {
            throw Error.notFound
        }
        for typeContextDescriptor in typeContextDescriptors {
            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machOFile)
            print("----------------------------------------")
            try print(typeContextDescriptor.flags.kind, typeContextDescriptor.name(in: machOFile), "{")
            let records = try fieldDescriptor.records(in: machOFile)
            for (index, record) in records.enumerated() {
                let mangledTypeName = try record.mangledTypeName(in: machOFile).stringValue()
                var demangledTypeName = mangledTypeName.demangled
                var fieldName = try record.fieldName(in: machOFile)
                let isLazy = fieldName.hasPrefix("$__lazy_storage_$_")
                let isWeak = demangledTypeName.hasPrefix("weak ")
                fieldName = fieldName.replacingOccurrences(of: "$__lazy_storage_$_", with: "")
                demangledTypeName = demangledTypeName.replacingOccurrences(of: "weak ", with: "")
                if typeContextDescriptor.flags.kind == .enum {
                    print("    ", mangledTypeName)
                    
                    print("    ", "\(record.flags.contains(.isIndirectCase) ? "indirect " : "")case", "\(fieldName)\(demangledTypeName)")
                } else {
                    print("    ", mangledTypeName)

                    print("    ", "\(record.flags.contains(.isVariadic) ? isLazy ? "lazy var" : isWeak ? "weak var" : "var" : "let")", "\(fieldName):", demangledTypeName)
                }

                if index != records.count - 1 {
                    print("")
                }
            }
            print("}")
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

    @Test func testSwiftTypeRefSection() async throws {
        let loadCommands = machOFile.loadCommands

        let __section: any SectionProtocol
        if let text = loadCommands.text64,
           let section = text.__swift5_typeref(in: machOFile) {
            __section = section
        } else if let text = loadCommands.text,
                  let section = text.__swift5_typeref(in: machOFile) {
            __section = section
        } else {
            return
        }

        let startOffset = __section.offset
        let endOffset = startOffset + __section.size
        var currentOffset = startOffset
        while currentOffset < endOffset {
            let mangledName = try machOFile.readSymbolicMangledName(at: currentOffset)
            print(mangledName.stringValue())
            currentOffset += mangledName.endOffset - mangledName.startOffset
        }
    }

    @Test func test() async throws {
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
