import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@_spi(Internals) import MachOCodeReferences
@testable import CrossReferenceAnalysis

/// Code that builds a function's address references the function, and a
/// query for the function's callers lists it beside the calls (evolution
/// proposal `cross-reference-recall-gaps`): the callback handed to
/// `dispatch_async_f`, the invoke function of a block built on the stack.
@Suite
struct FunctionAddressReferenceTests {
    private static let source = """
    #include <dispatch/dispatch.h>
    extern void consume(int value);
    __attribute__((noinline)) void work(void *context) { consume((int)(long)context); }
    void scheduleWork(void) { dispatch_async_f(dispatch_get_main_queue(), 0, work); }
    void callWork(void) { work(0); }
    void scheduleBlock(int value) { dispatch_async(dispatch_get_main_queue(), ^{ consume(value); }); }
    """

    private static func analyzer() throws -> CrossReferenceAnalyzer {
        let library = try FixtureCompiler.shared.dynamicLibrary(
            named: "FunctionAddressReferences",
            language: .c,
            sourceFiles: [FixtureSourceFile(name: "FunctionAddressReferences.c", contents: source)],
            arguments: ["-arch", "arm64", "-O2", "-fblocks", "-Wl,-undefined,dynamic_lookup"]
        )
        return try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: library)])
    }

    private static func function(where matches: (String) -> Bool, in analyzer: CrossReferenceAnalyzer) throws -> CodeFunction {
        try #require(analyzer.functions(inImageAt: 0).first { if case .symbol(let symbol)? = $0.name { matches(symbol) } else { false } })
    }

    @Test func functionQueriesReturnCallsAndAddressTakingSites() throws {
        let analyzer = try Self.analyzer()
        let work = try Self.function(where: { $0 == "_work" }, in: analyzer)
        let scheduleWork = try Self.function(where: { $0 == "_scheduleWork" }, in: analyzer)
        let callWork = try Self.function(where: { $0 == "_callWork" }, in: analyzer)
        let references = analyzer.references(to: [.function(work.location)], inImageAt: 0)
        // `callWork` calls it, or branches to it.
        #expect(references.contains { $0.function == callWork.location && $0.kind != .reference })
        // `scheduleWork` builds its address for `dispatch_async_f`.
        let taken = references.filter { $0.function == scheduleWork.location }
        #expect(taken.count == 1)
        #expect(taken.first?.kind == .reference)
        #expect(taken.first?.route == .addressMaterialization)
    }

    @Test func aStackBlockIsReferencedByTheFunctionThatBuildsIt() throws {
        let analyzer = try Self.analyzer()
        let scheduleBlock = try Self.function(where: { $0 == "_scheduleBlock" }, in: analyzer)
        let invoke = try Self.function(where: { $0.hasPrefix("___scheduleBlock_block_invoke") }, in: analyzer)
        let references = analyzer.references(to: [.function(invoke.location)], inImageAt: 0)
        #expect(references.contains { $0.function == scheduleBlock.location && $0.kind == .reference })
    }

    /// The whole image's table carries them too.
    @Test func theWholeTableHoldsFunctionAddressReferences() throws {
        let analyzer = try Self.analyzer()
        let work = try Self.function(where: { $0 == "_work" }, in: analyzer)
        let table = analyzer.referenceTable(ofImageAt: 0)
        #expect(table.references(to: .function(work.location)).contains { $0.kind == .reference })
    }
}
