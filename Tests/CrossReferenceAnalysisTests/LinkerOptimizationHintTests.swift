import Foundation
import Testing
import MachOKit
import ARM64InstructionDecoding
@testable import CrossReferenceAnalysis

/// Code the linker rewrote after it laid the image out.
///
/// ld64 — the linker of Xcode 14 and earlier, and of Xcode 15 and 16 with
/// `-ld_classic` — follows the compiler's linker optimization hints: an
/// `adrp` / `ldr` pair whose slot lies within a megabyte of the load becomes
/// `nop` / `ldr xN, <slot>`, an `adrp` / `add` pair `adr xN, <address>` /
/// `nop`, and a lazily bound stub `nop` / `ldr x16, <slot>` / `br x16`. A
/// third-party app linked that way reaches its selectors, its classes and
/// every imported function only through those shapes: Asset Catalog Viewer,
/// built with the macOS 12 SDK, loads 357 selectors and 71 classes straight
/// from their slots, and every one of its stubs is rewritten.
///
/// Xcode 26's linker applies no hint and Xcode 27 ships no `ld-classic`, so
/// each fixture is linked as usual and then rewritten here the way ld64
/// rewrites it.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct LinkerOptimizationHintTests {
    private struct Fixtures {
        let analyzer: CrossReferenceAnalyzer
        let objectiveCImage: Int
        let stubImage: Int

        func function(named name: String, inImageAt imageIndex: Int) throws -> CodeFunction {
            try #require(analyzer.functions(inImageAt: imageIndex).first { $0.name == .symbol(name) }, "no function \(name)")
        }
    }

    /// Both libraries, loaded before the analyzer that reads them is made.
    private static let fixtures = Result<Fixtures, any Error> {
        try CompiledFixture.load(
            libraryName: "libCrossReferenceLinkerHints.dylib",
            sources: [
                "Probe.m": """
                #import <Foundation/Foundation.h>

                @interface CrossReferenceLinkerHintProbe : NSObject
                @end

                @implementation CrossReferenceLinkerHintProbe
                @end

                id crossReferenceSendsThroughALiteralSelectorLoad(id object) {
                    return [object description];
                }

                Class crossReferenceLoadsAClassThroughALiteral(void) {
                    return [CrossReferenceLinkerHintProbe class];
                }
                """,
                "Probe.s": """
                    .section __TEXT,__text,regular,pure_instructions
                    .globl _crossReferenceAddressesAClassDirectly
                    .p2align 2
                _crossReferenceAddressesAClassDirectly:
                    adrp x0, _OBJC_CLASS_$_CrossReferenceLinkerHintProbe@PAGE
                    add x0, x0, _OBJC_CLASS_$_CrossReferenceLinkerHintProbe@PAGEOFF
                    ret
                """,
            ],
            compilerArguments: ["-O1", "-mmacosx-version-min=12.0", "-fno-objc-arc", "-fno-objc-msgsend-selector-stubs", "-framework", "Foundation"]
        ) { bytes, machO in
            let rewrite = try LinkerRewrite(machO: machO)
            try rewrite.loadStraightFromTheSlot(into: 1, inFunctionNamed: "_crossReferenceSendsThroughALiteralSelectorLoad", of: &bytes)
            try rewrite.loadStraightFromTheSlot(into: 0, inFunctionNamed: "_crossReferenceLoadsAClassThroughALiteral", of: &bytes)
            try rewrite.addressDirectly(into: 0, inFunctionNamed: "_crossReferenceAddressesAClassDirectly", of: &bytes)
        }
        // A stub is shared by every call to its function, so the stub fixture
        // imports nothing a send needs.
        try CompiledFixture.load(
            libraryName: "libCrossReferenceRewrittenStub.dylib",
            sources: ["Stub.c": "#include <stdio.h>\nvoid crossReferenceCallsThroughARewrittenStub(void) { puts(\"called\"); }\n"],
            compilerArguments: ["-O1", "-mmacosx-version-min=12.0"]
        ) { bytes, machO in
            try LinkerRewrite(machO: machO).loadEveryStubStraightFromItsSlot(of: &bytes)
        }
        guard let analyzer = CrossReferenceAnalyzer(),
              let objectiveCImage = analyzer.imagePaths.firstIndex(where: { $0.hasSuffix("/libCrossReferenceLinkerHints.dylib") }),
              let stubImage = analyzer.imagePaths.firstIndex(where: { $0.hasSuffix("/libCrossReferenceRewrittenStub.dylib") })
        else { throw CompiledFixture.Failure(description: "the analyzer does not see the fixtures") }
        return Fixtures(analyzer: analyzer, objectiveCImage: objectiveCImage, stubImage: stubImage)
    }

    @Test func aSelectorLoadedStraightFromItsSlotNamesTheSend() throws {
        let fixtures = try Self.fixtures.get()
        let function = try fixtures.function(named: "_crossReferenceSendsThroughALiteralSelectorLoad", inImageAt: fixtures.objectiveCImage)
        let targets = fixtures.analyzer.references(madeBy: function).map(\.target)
        #expect(targets.contains(.messageSend(selector: "description", receiver: .unknown)), "\(targets)")
    }

    @Test func aClassLoadedStraightFromItsSlotIsReferenced() throws {
        let fixtures = try Self.fixtures.get()
        let function = try fixtures.function(named: "_crossReferenceLoadsAClassThroughALiteral", inImageAt: fixtures.objectiveCImage)
        let references = fixtures.analyzer.references(madeBy: function)
        #expect(references.contains { Self.isReference(to: "CrossReferenceLinkerHintProbe", $0) }, "\(references.map(\.target))")
    }

    @Test func aClassAddressedWithAdrIsReferenced() throws {
        let fixtures = try Self.fixtures.get()
        let function = try fixtures.function(named: "_crossReferenceAddressesAClassDirectly", inImageAt: fixtures.objectiveCImage)
        let references = fixtures.analyzer.references(madeBy: function)
        #expect(references.contains { Self.isReference(to: "CrossReferenceLinkerHintProbe", $0) }, "\(references.map(\.target))")
    }

    /// MachOKit reads no slot from a rewritten stub; the call reached only
    /// the stub's imported name.
    @Test func aRewrittenStubReachesItsTarget() throws {
        let fixtures = try Self.fixtures.get()
        let function = try fixtures.function(named: "_crossReferenceCallsThroughARewrittenStub", inImageAt: fixtures.stubImage)
        let call = try #require(fixtures.analyzer.references(madeBy: function).first)
        guard case .function(let location) = call.target else {
            Issue.record("the call through the rewritten stub resolved to \(call.target), not to a function")
            return
        }
        #expect(fixtures.analyzer.imagePaths[location.imageIndex].hasSuffix("/libsystem_c.dylib"))
        let callee = try #require(fixtures.analyzer.function(containing: location))
        let names = (callee.name.map { [$0] } ?? []) + callee.foldedSymbolNames.map { .symbol($0) }
        #expect(names.contains(.symbol("_puts")), "callee named \(names)")
    }

    private static func isReference(to className: String, _ reference: CodeReference) -> Bool {
        guard reference.kind == .reference, case .objectiveCClass(let name, _) = reference.target else { return false }
        return name == className
    }
}

/// ld64's rewrites of a linked library's code, applied to its bytes.
private struct LinkerRewrite {
    private struct CodeRange {
        let address: UInt64
        let size: UInt64
        let fileOffset: Int
    }

    private let text: CodeRange
    private let stubs: CodeRange?
    /// The functions' starts, by symbol.
    private let functionStarts: [String: UInt64]

    init(machO: MachOFile) throws {
        func codeRange(named sectionName: String) -> CodeRange? {
            machO.sections64.first { $0.segmentName == "__TEXT" && $0.sectionName == sectionName }.map {
                CodeRange(address: UInt64($0.address), size: UInt64($0.size), fileOffset: $0.offset)
            }
        }
        guard let text = codeRange(named: "__text") else { throw CompiledFixture.Failure(description: "no __text") }
        self.text = text
        self.stubs = codeRange(named: "__stubs")
        var functionStarts: [String: UInt64] = [:]
        // A file symbol's offset is its n_value — an address.
        for symbol in machO.symbols where UInt64(symbol.offset) >= text.address && UInt64(symbol.offset) < text.address + text.size {
            functionStarts[symbol.name] = UInt64(symbol.offset)
        }
        self.functionStarts = functionStarts
    }

    /// `adrp xN, page` / … / `ldr x<destination>, [xN, #offset]` → `nop` /
    /// … / `ldr x<destination>, <page + offset>`, for the first such pair in
    /// the function.
    func loadStraightFromTheSlot(into destination: Int, inFunctionNamed name: String, of bytes: inout Data) throws {
        for (pageAddress, page) in try pageMaterializations(inFunctionNamed: name, of: bytes) {
            for loadAddress in stride(from: pageAddress + 4, to: try end(ofFunctionNamed: name), by: 4) {
                guard let load = ARM64InstructionWord.load(word(at: loadAddress, of: bytes)),
                      load.base == page.destination, load.destination == destination, !load.writesBack
                else { continue }
                let slot = ARM64InstructionWord.adding(load.displacement, to: page.address)
                try requireMegabyteReach(from: loadAddress, to: slot)
                setWord(ARM64InstructionWord.noOperation, at: pageAddress, of: &bytes)
                setWord(InstructionEncoding.loadLiteral(destination, at: loadAddress, slot: slot), at: loadAddress, of: &bytes)
                return
            }
        }
        throw CompiledFixture.Failure(description: "\(name) loads x\(destination) through no adrp / ldr pair")
    }

    /// `adrp x<destination>, page` / `add x<destination>, x<destination>,
    /// #offset` → `adr x<destination>, <page + offset>` / `nop`.
    func addressDirectly(into destination: Int, inFunctionNamed name: String, of bytes: inout Data) throws {
        for (pageAddress, page) in try pageMaterializations(inFunctionNamed: name, of: bytes) where page.destination == destination {
            guard let arithmetic = ARM64InstructionWord.addImmediate(word(at: pageAddress + 4, of: bytes)),
                  arithmetic.source == destination, arithmetic.destination == destination
            else { continue }
            let target = ARM64InstructionWord.adding(arithmetic.addend, to: page.address)
            try requireMegabyteReach(from: pageAddress, to: target)
            setWord(InstructionEncoding.adr(destination, at: pageAddress, target: target), at: pageAddress, of: &bytes)
            setWord(ARM64InstructionWord.noOperation, at: pageAddress + 4, of: &bytes)
            return
        }
        throw CompiledFixture.Failure(description: "\(name) builds x\(destination) with no adrp / add pair")
    }

    /// Every `adrp x16, page` / `ldr x16, [x16, #offset]` / `br x16` stub →
    /// `nop` / `ldr x16, <page + offset>` / `br x16`.
    func loadEveryStubStraightFromItsSlot(of bytes: inout Data) throws {
        guard let stubs, stubs.size > 0 else { throw CompiledFixture.Failure(description: "no __stubs") }
        for stubAddress in stride(from: stubs.address, to: stubs.address + stubs.size, by: 12) {
            guard let page = ARM64InstructionWord.addressMaterialization(word(at: stubAddress, of: bytes), at: stubAddress), page.destination == 16,
                  let load = ARM64InstructionWord.load(word(at: stubAddress + 4, of: bytes)), load.base == 16, load.destination == 16,
                  word(at: stubAddress + 8, of: bytes) == InstructionEncoding.branchToRegister(16)
            else { throw CompiledFixture.Failure(description: "the stub at \(String(stubAddress, radix: 16)) is no adrp / ldr / br") }
            let slot = ARM64InstructionWord.adding(load.displacement, to: page.address)
            try requireMegabyteReach(from: stubAddress + 4, to: slot)
            setWord(ARM64InstructionWord.noOperation, at: stubAddress, of: &bytes)
            setWord(InstructionEncoding.loadLiteral(16, at: stubAddress + 4, slot: slot), at: stubAddress + 4, of: &bytes)
        }
    }

    /// Every `adrp` in the function, in address order.
    private func pageMaterializations(inFunctionNamed name: String, of bytes: Data) throws -> [(UInt64, (destination: Int, address: UInt64))] {
        guard let start = functionStarts[name] else { throw CompiledFixture.Failure(description: "no function \(name)") }
        return try stride(from: start, to: end(ofFunctionNamed: name), by: 4).compactMap { address in
            guard let page = ARM64InstructionWord.addressMaterialization(word(at: address, of: bytes), at: address), page.isPageAddress else { return nil }
            return (address, (page.destination, page.address))
        }
    }

    private func end(ofFunctionNamed name: String) throws -> UInt64 {
        guard let start = functionStarts[name] else { throw CompiledFixture.Failure(description: "no function \(name)") }
        return functionStarts.values.filter { $0 > start }.min() ?? text.address + text.size
    }

    private func requireMegabyteReach(from address: UInt64, to target: UInt64) throws {
        let distance = Int64(bitPattern: target &- address)
        guard distance >= -(1 << 20), distance < 1 << 20 else {
            throw CompiledFixture.Failure(description: "\(String(target, radix: 16)) lies beyond a megabyte of \(String(address, radix: 16))")
        }
    }

    private func fileOffset(of address: UInt64) -> Int {
        for range in [text, stubs].compactMap({ $0 }) where address >= range.address && address < range.address + range.size {
            return range.fileOffset + Int(address - range.address)
        }
        preconditionFailure("\(String(address, radix: 16)) lies in no code section")
    }

    private func word(at address: UInt64, of bytes: Data) -> UInt32 {
        let offset = fileOffset(of: address)
        return UInt32(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
    }

    private func setWord(_ word: UInt32, at address: UInt64, of bytes: inout Data) {
        let offset = fileOffset(of: address)
        withUnsafeBytes(of: word.littleEndian) { bytes.replaceSubrange(offset ..< offset + 4, with: $0) }
    }
}
