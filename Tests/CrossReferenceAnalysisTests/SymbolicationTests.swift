import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences
@_spi(Internals) import ARM64InstructionDecoding
@testable import CrossReferenceAnalysis

/// What an address is (evolution proposal
/// `offline-cross-references-and-symbolication`, step 6).
@Suite
struct SymbolicationTests {
    /// SwiftUICore's image stubs in the macOS 26.7 cache: each is
    /// symbolicated by the slot it loads — where `dyld_info` and MachOKit's
    /// reading of the indirect symbol table name 2,195 of them wrongly. Five
    /// of those, checked against `ipsw dyld macho --stubs`, which follows
    /// the slots too: the indirect symbol table gives all five one SwiftUI
    /// witness's name, and they call Accelerate's `Quadrature`.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Volumes/DyldSharedCaches/macOS/26.7/dyld_shared_cache_arm64e"), "needs the archived macOS 26.7 cache"))
    func symbolicatesSwiftUICoreAuthStubsByTheirSlotsNotTheirIndirectSymbols() throws {
        let cache = try FullDyldCache(url: URL(fileURLWithPath: "/Volumes/DyldSharedCaches/macOS/26.7/dyld_shared_cache_arm64e"))
        let analyzer = try CrossReferenceAnalyzer(dyldCache: cache)
        let swiftUICore = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/SwiftUICore.framework/Versions/A/SwiftUICore") })
        let file = try #require(analyzer.imageSet.images[swiftUICore].reader.asMachOFile)
        func names(at location: CodeLocation) -> Set<String> {
            guard let function = analyzer.function(containing: location) else { return [] }
            return Set([function.name.map(CrossReferenceAnalyzer.spelling(of:))].compactMap { $0 } + function.foldedSymbolNames)
                .union(analyzer.exportedNames(at: location))
        }

        let checkedByIpsw: [UInt64: String] = [
            0x22E6_BA9D0: "_$s10Accelerate10QuadratureV10IntegratorOMa",
            0x22E6_BAA10: "_$s10Accelerate10QuadratureVMa",
            0x22E6_BA9F0: "_$s10Accelerate10QuadratureV5ErrorOMa",
            0x22E6_BA9E0: "_$s10Accelerate10QuadratureV10integrator17absoluteTolerance08relativeE0A2C10IntegratorO_S2dtcfC",
            0x22E6_BAA00: "_$s10Accelerate10QuadratureV9integrate4over9integrands6ResultOySd08integralF0_Sd22estimatedAbsoluteErrortAC0J0OGSNySdG_S2dXEtF",
        ]
        let symbols = Array(file.symbols)
        let indirectSymbols = file.indirectSymbols.map(Array.init) ?? []
        let stubs = file.sections64.filter { $0.sectionName == "__auth_stubs" }.flatMap { $0.stubs(in: file).map(Array.init) ?? [] }
        for (stubAddress, expectedName) in checkedByIpsw {
            guard case .stub(let hops, .function(let location)) = analyzer.symbolication(of: stubAddress).meaning else {
                Issue.record("\(String(stubAddress, radix: 16)): \(analyzer.symbolication(of: stubAddress).meaning)")
                continue
            }
            #expect(hops == [stubAddress])
            #expect(names(at: location).contains(expectedName), "\(String(stubAddress, radix: 16)): \(names(at: location))")
            // What the indirect symbol table says instead.
            if let stub = stubs.first(where: { $0.address == stubAddress }), let indirectIndex = stub.indirectSymbolIndex, indirectIndex < indirectSymbols.count,
               let symbolIndex = indirectSymbols[indirectIndex].index, symbolIndex < symbols.count {
                #expect(symbols[symbolIndex].name != expectedName)
            }
        }

        var resolvedStubCount = 0
        for stub in stubs {
            guard case .stub(let hops, let target) = analyzer.symbolication(of: stub.address).meaning, hops == [stub.address] else {
                Issue.record("\(String(stub.address, radix: 16)) is no stub")
                continue
            }
            switch target {
            case .function, .importedSymbol: resolvedStubCount += 1
            default: break
            }
        }
        #expect(resolvedStubCount > 1000 && resolvedStubCount == stubs.count, "\(resolvedStubCount) of \(stubs.count) stubs resolved")
    }

    /// macOS 27's AppKit sends through stubs the whole cache shares: a
    /// selector stub, which puts the selector in `x1` and is the message it
    /// sends, or a GOT stub, which leads to `objc_msgSend` — or to a libobjc
    /// entry point that stands for a send — and leaves the selector to the
    /// caller.
    @Test(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
    func symbolicatesCacheSharedMessageSendStubToItsSelector() throws {
        let analyzer = try #require(SharedAnalyzer.analyzer)
        let appKit = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/AppKit.framework/Versions/C/AppKit") })
        let sends = analyzer.referenceTable(ofImageAt: appKit).references.filter { reference in
            guard reference.route == .cacheSharedStub, case .messageSend = reference.target else { return false }
            return true
        }
        try #require(!sends.isEmpty, "AppKit sends through no cache-shared stub on this system")
        var selectorStubCount = 0
        var globalOffsetTableStubCount = 0
        for send in sends.prefix(2000) {
            guard case .messageSend(let selector, _) = send.target,
                  let word = analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: appKit, address: send.instructionAddress))),
                  let stub = ARM64InstructionWord.callTarget(word, at: send.instructionAddress) ?? ARM64InstructionWord.branchTarget(word, at: send.instructionAddress)
            else { continue }
            let symbolication = analyzer.symbolication(of: stub)
            #expect(symbolication.imagePath == nil)
            switch symbolication.meaning {
            case .stub(let hops, .messageSend(let stubSelector, _)):
                #expect(hops == [stub] && stubSelector == selector)
                selectorStubCount += 1
            case .stub(let hops, .function(let location)):
                #expect(hops.first == stub)
                // `objc_msgSend`, or a libobjc entry point that stands for a
                // send: `objc_alloc_init`, `objc_opt_class`.
                let names = [analyzer.function(containing: location)?.name.map(CrossReferenceAnalyzer.spelling(of:))].compactMap { $0 } + analyzer.exportedNames(at: location)
                #expect(names.contains { $0.hasPrefix("_objc_") }, "\(String(stub, radix: 16)) leads to \(names)")
                globalOffsetTableStubCount += 1
            default:
                Issue.record("\(String(stub, radix: 16)): \(symbolication.meaning)")
            }
        }
        #expect(selectorStubCount > 0, "no send of AppKit's first 2,000 through a cache-shared selector stub")
        #expect(selectorStubCount + globalOffsetTableStubCount > 100)
    }

    /// A standalone library's GOT slot binds by name: to a symbol of a
    /// library the analyzer does not cover, or — linked `-interposable` — to
    /// its own function.
    @Test func symbolicatesGlobalOffsetTableSlotToItsBoundSymbol() throws {
        let (directory, library) = try CompiledFixture.build(
            libraryName: "libSlots.dylib",
            sources: ["Slots.c": """
            #include <stdio.h>
            __attribute__((noinline)) int slotCallee(int value) { return value * 5; }
            int slotCaller(int value) { puts("calling"); return slotCallee(value); }
            """],
            compilerArguments: ["-O1", "-Wl,-interposable"]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try MachOFile(url: library)
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file])
        let callee = try #require(analyzer.functions(inImageAt: 0).first { $0.name == .symbol("_slotCallee") })
        var targets: [CodeReferenceTarget] = []
        for section in file.sections64 where section.sectionName == "__got" || section.sectionName == "__auth_got" {
            for slot in stride(from: UInt64(section.address), to: UInt64(section.address) + UInt64(section.size), by: 8) {
                let symbolication = analyzer.symbolication(of: slot)
                #expect(symbolication.sectionName == section.sectionName)
                guard case .pointerSlot(.globalOffsetTable, let target) = symbolication.meaning else {
                    Issue.record("\(String(slot, radix: 16)): \(symbolication.meaning)")
                    continue
                }
                targets.append(target)
            }
        }
        #expect(targets.contains(.importedSymbol(name: "_puts")), "\(targets)")
        #expect(targets.contains(.function(callee.location)), "\(targets)")
    }

    /// Inside a function the symbol table leaves unnamed: the name its
    /// Objective-C method list gives it, and the offset into it.
    @Test(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
    func symbolicatesAnAddressInsideAnUnnamedFunctionWithItsFallbackName() throws {
        let analyzer = try #require(SharedAnalyzer.analyzer)
        let matter = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/Matter.framework/Versions/A/Matter") })
        let function = try #require(analyzer.functions(inImageAt: matter).first { function in
            if case .objectiveCMethod = function.name { function.size > 8 } else { false }
        }, "Matter has no function its method lists alone name")
        let symbolication = analyzer.symbolication(of: function.location.address + 4)
        #expect(symbolication.imagePath == analyzer.imagePaths[matter])
        #expect(symbolication.sectionName == "__text")
        #expect(symbolication.meaning == .function(start: function.location, name: function.name.map(CrossReferenceAnalyzer.spelling(of:)), offset: 4))
    }

    /// No image maps it: nothing is made up. Read from the cache file: in
    /// the process, an image outside the cache linked at 0 — the test
    /// bundle — holds the unslid address 0x10, its own Mach header.
    @Test(.enabled(if: RunningCacheFileAnalyzer.analyzer != nil, "needs the running system's dyld shared cache file"))
    func symbolicatesAnUnmappedAddressAsUnmapped() throws {
        let analyzer = try #require(RunningCacheFileAnalyzer.analyzer)
        for address: UInt64 in [0x10, 0x7FFF_0000_0000] {
            let symbolication = analyzer.symbolication(of: address)
            #expect(symbolication.meaning == .unmapped, "\(String(address, radix: 16)): \(symbolication.meaning)")
            #expect(symbolication.imagePath == nil)
        }
    }

    /// Strings, an instance variable's offset variable and a selector
    /// reference, in a library compiled for the test.
    @Test func symbolicatesStringsAndObjectiveCSlots() throws {
        let (directory, library) = try CompiledFixture.build(
            libraryName: "libObjectiveCSlots.dylib",
            sources: ["Slots.m": """
            #import <Foundation/Foundation.h>
            @interface Holder : NSOperation { @public long _held; }
            @end
            @implementation Holder
            @end
            long readHeld(Holder *holder) { return holder->_held; }
            const char *cString(void) { return "symbolicated characters"; }
            NSString *constantString(void) { return @"symbolicated constant"; }
            """],
            compilerArguments: ["-O1", "-fobjc-arc", "-framework", "Foundation"]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try MachOFile(url: library)
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file], recordingStringReferences: true)
        let references = analyzer.referenceTable(ofImageAt: 0).references
        func symbolicationOfAddressBuiltFor(_ target: CodeReferenceTarget) throws -> AddressSymbolication {
            let reference = try #require(references.first { $0.target == target }, "\(target)")
            // `adrp` / `add`: the `add` holds the address.
            let word = try #require(analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: 0, address: reference.instructionAddress))))
            let previousWord = try #require(analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: 0, address: reference.instructionAddress - 4))))
            let page = try #require(ARM64InstructionWord.addressMaterialization(previousWord, at: reference.instructionAddress - 4))
            let addend = try #require(ARM64InstructionWord.addImmediate(word))
            return analyzer.symbolication(of: ARM64InstructionWord.adding(addend.addend, to: page.address))
        }
        #expect(try symbolicationOfAddressBuiltFor(.cString("symbolicated characters")).meaning == .cString("symbolicated characters"))
        #expect(try symbolicationOfAddressBuiltFor(.constantString("symbolicated constant")).meaning == .constantString("symbolicated constant"))
        let instanceVariables = try #require(file.sections64.first { $0.sectionName == "__objc_ivar" })
        #expect(analyzer.symbolication(of: UInt64(instanceVariables.address)).meaning == .pointerSlot(.instanceVariableOffset, target: .objectiveCInstanceVariable(className: "Holder", name: "_held")))
    }
}
