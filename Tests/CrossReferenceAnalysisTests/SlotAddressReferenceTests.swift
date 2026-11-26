import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
@_spi(Internals) import MachOCodeReferences
@testable import CrossReferenceAnalysis

/// Optimized Swift code hands an Objective-C class's GOT slot to the merged
/// helper that makes the class's metadata (`$sSo…CMaTm`), building only the
/// slot's address: `adrp x2; add x2, <slot>; bl`. That `add` references the
/// class (evolution proposal `cross-reference-recall-gaps`; ControlCenter
/// 26.7 has 554 such calls).
@Suite
struct SlotAddressReferenceTests {
    private static func analyzer() throws -> (analyzer: CrossReferenceAnalyzer, machO: MachOFile) {
        let library = try FixtureCompiler.shared.dynamicLibrary(
            named: "SlotAddressReferences",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "SlotAddressReferences.swift", contents: """
            import Foundation
            public func descriptorClass() -> Any.Type { NSAppleEventDescriptor.self }
            public func timerClass() -> Any.Type { Timer.self }
            """)],
            arguments: ["-O", "-swift-version", "5"]
        )
        let machO = try MachOFile(url: library)
        return (try CrossReferenceAnalyzer(machOFiles: [machO]), machO)
    }

    /// In a file analyzed without Foundation, the slot binds to an imported
    /// class: the reference a `refs --class NSTimer` query also takes.
    @Test func slotAddressHandedToAHelperIsAClassReference() throws {
        let (analyzer, _) = try Self.analyzer()
        let timerClass = try #require(analyzer.functions(inImageAt: 0).first { function in
            if case .symbol(let symbol)? = function.name { symbol.hasPrefix("_$s21SlotAddressReferences10timerClass") } else { false }
        })
        let references = analyzer.references(to: [.objectiveCClass("NSTimer"), .importedSymbol("_OBJC_CLASS_$_NSTimer")], inImageAt: 0)
        let inTimerClass = references.filter { $0.function == timerClass.location }
        #expect(inTimerClass.count == 1)
        #expect(inTimerClass.first?.target == .importedSymbol(name: "_OBJC_CLASS_$_NSTimer"))
        #expect(inTimerClass.first?.kind == .reference)
        #expect(inTimerClass.first?.route == .pointerSlot)
    }
}
