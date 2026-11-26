import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@_spi(Internals) import MachOCodeReferences
@testable import CrossReferenceAnalysis

/// A selector code loads but sends nothing with is a selector reference,
/// filed under the selector's key beside its sends (evolution proposal
/// `cross-reference-recall-gaps`): an argument of `respondsToSelector:` or
/// `performSelector:`, a returned selector.
@Suite
struct SelectorReferenceTests {
    private static let source = """
    #import <Foundation/Foundation.h>
    BOOL probeResponds(id object) {
        return [object respondsToSelector:@selector(coalescingNodeObserver:openSyncCompleted:)];
    }
    SEL probeReturnsSelector(void) {
        return @selector(name);
    }
    id probePerforms(id object) {
        return [object performSelector:@selector(copy)];
    }
    """

    /// Classic sends: the selector references are loaded in the functions
    /// themselves, the shape a selector stub hides.
    private static func analyzer() throws -> CrossReferenceAnalyzer {
        let library = try FixtureCompiler.shared.dynamicLibrary(
            named: "SelectorReferences",
            language: .c,
            sourceFiles: [FixtureSourceFile(name: "SelectorReferences.m", contents: source)],
            arguments: ["-arch", "arm64", "-O2", "-fno-objc-msgsend-selector-stubs", "-framework", "Foundation"]
        )
        return try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: library)])
    }

    private static func function(named name: String, in analyzer: CrossReferenceAnalyzer) throws -> CodeFunction {
        try #require(analyzer.functions(inImageAt: 0).first { if case .symbol(name)? = $0.name { true } else { false } })
    }

    @Test func selectorQueriesReturnSendsAndSelectorReferences() throws {
        let analyzer = try Self.analyzer()
        let performs = try Self.function(named: "_probePerforms", in: analyzer)
        let copies = analyzer.references(to: [.selector("copy")], inImageAt: 0)
        #expect(copies.map(\.target) == [.selector("copy")])
        #expect(copies.allSatisfy { $0.function == performs.location && $0.kind == .reference })
        let performSelectors = analyzer.references(to: [.selector("performSelector:")], inImageAt: 0)
        #expect(performSelectors.contains { if case .messageSend("performSelector:", _) = $0.target { true } else { false } })
        #expect(!performSelectors.contains { $0.target == .selector("performSelector:") })
        #expect(analyzer.references(to: [.selector("name")], inImageAt: 0).map(\.target) == [.selector("name")])
        #expect(analyzer.references(to: [.selector("coalescingNodeObserver:openSyncCompleted:")], inImageAt: 0).map(\.target) == [.selector("coalescingNodeObserver:openSyncCompleted:")])
    }

    @Test func selectorReferencesSurviveTheCompactIndex() throws {
        let analyzer = try Self.analyzer()
        let index = analyzer.referenceIndex(ofImageAt: 0)
        for selector in ["copy", "name", "performSelector:"] {
            #expect(Set(index.references(to: [.selector(selector)])) == Set(analyzer.references(to: [.selector(selector)], inImageAt: 0)), "\(selector)")
        }
    }

    /// Recorded when the scan leaves the function, a selector reference is
    /// listed where its instruction lies among the function's references.
    @Test func aFunctionsReferencesStayInInstructionOrder() throws {
        let analyzer = try Self.analyzer()
        let references = try analyzer.references(madeBy: Self.function(named: "_probePerforms", in: analyzer))
        #expect(references.contains { $0.target == .selector("copy") })
        #expect(references.map(\.instructionAddress) == references.map(\.instructionAddress).sorted())
    }

    @Test func symbolicationCallsASelectorReferenceSlotASelector() throws {
        let analyzer = try Self.analyzer()
        let library = try FixtureCompiler.shared.dynamicLibrary(
            named: "SelectorReferences",
            language: .c,
            sourceFiles: [FixtureSourceFile(name: "SelectorReferences.m", contents: Self.source)],
            arguments: ["-arch", "arm64", "-O2", "-fno-objc-msgsend-selector-stubs", "-framework", "Foundation"]
        )
        let machO = try MachOFile(url: library)
        let selectorReferences = try #require(machO.sections64.first { $0.segmentName == "__DATA" && $0.sectionName == "__objc_selrefs" })
        let meaning = analyzer.symbolication(of: UInt64(selectorReferences.address), inImageAt: 0).meaning
        guard case .pointerSlot(.selectorReference, let target) = meaning, case .selector = target else {
            Issue.record("\(meaning)")
            return
        }
    }
}
