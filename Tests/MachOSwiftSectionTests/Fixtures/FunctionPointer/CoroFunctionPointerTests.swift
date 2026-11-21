import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `CoroFunctionPointer`.
///
/// Unlike every other Suite here this one compiles its own fixture. A `…Twc`
/// record only exists for a `yield_once_2` coroutine, which needs the
/// CoroutineAccessors feature, and `SymbolTestsCore` is not built with it —
/// nor can it be: turning the flag on would change the fixture's layout and
/// move every implementation offset the checked-in ABI baselines pin (AGENTS.md
/// records the same class of accident for `CODE_SIGNING_ALLOWED=NO`).
///
/// Consequently the assertions are structural rather than literal: the
/// concrete offsets depend on the toolchain that ran the compile, so what is
/// pinned is the record's shape and the invariants that make it meaningful —
/// 16 bytes, a function pointer that resolves into `__TEXT,__text` and is
/// never the record's own address, and a non-zero frame size.
@Suite
final class CoroFunctionPointerTests: FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "CoroFunctionPointer"

    /// Declared as a literal rather than read from a baseline: this Suite
    /// pins no baseline, for the reason in the Suite comment.
    static let registeredTestMethodNames: Set<String> = [
        "functionAddress",
        "layout",
        "offset",
    ]

    // MARK: - Fixture

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class"). `Holder.first` is
    /// the payload: a `_read` accessor, which under CoroutineAccessors lowers
    /// to a callee-allocated coroutine and therefore gets a `…Twc` record.
    private static let fixtureSource = """
    public final class Anchor {
        public init() {}
    }

    public struct Holder {
        private var storage: [Int] = []

        public init() {}

        public var first: Int {
            _read { yield storage[0] }
            _modify { yield &storage[0] }
        }
    }
    """

    /// Both compiles failed; carries what each one reported.
    private struct BothCompilationsFailedError: Swift.Error, CustomStringConvertible {
        let withFeatureFlagFailure: any Swift.Error
        let withoutFeatureFlagFailure: any Swift.Error
        var description: String { "coro-function-pointer fixture compilation failed:\n\(withFeatureFlagFailure)\n\(withoutFeatureFlagFailure)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        // The feature is still experimental, so it must be requested by
        // name; should it ever graduate, the flag becomes unknown and the
        // compile fails, so fall back to building without it — the
        // accessors lower to `yield_once_2` either way once it is on by
        // default. `-enable-library-evolution` is what forces the
        // accessors to be dispatched (and therefore emitted) at all.
        func compile(withCoroutineAccessorsFlag requestsFeature: Bool) throws -> URL {
            try FixtureCompiler.shared.dynamicLibrary(
                named: "CoroFunctionPointerFixture",
                language: .swift,
                source: Self.fixtureSource,
                arguments: ["-enable-library-evolution"] + (requestsFeature ? ["-enable-experimental-feature", "CoroutineAccessors"] : [])
            )
        }

        let libraryURL: URL
        do {
            libraryURL = try compile(withCoroutineAccessorsFlag: true)
        } catch let withFeatureFlagFailure {
            do {
                libraryURL = try compile(withCoroutineAccessorsFlag: false)
            } catch let withoutFeatureFlagFailure {
                throw BothCompilationsFailedError(withFeatureFlagFailure: withFeatureFlagFailure, withoutFeatureFlagFailure: withoutFeatureFlagFailure)
            }
        }
        return try HostSlice.machOFile(at: libraryURL)
    }

    /// The one `…Twc` record in the fixture, plus the file it came from.
    ///
    /// Located by symbol suffix rather than by an exact mangled name: the
    /// accessor's mangling is not the point of this Suite, and pinning it
    /// would break on any spelling change in the demangler's grammar.
    private func loadRecord() throws -> (machOFile: MachOFile, record: CoroFunctionPointer) {
        let machOFile = try loadFixtureMachOFile()
        let symbol = try #require(
            machOFile.symbols.first(where: { symbol in
                symbol.nlist.flags?.stab == nil && symbol.name.hasSuffix("Twc")
            }),
            "the fixture carries no coro function pointer — CoroutineAccessors may no longer lower `_read` to `yield_once_2`"
        )
        return (machOFile, try CoroFunctionPointer.resolve(at: symbol.offset, in: machOFile.context))
    }

    /// File-offset range of `__TEXT,__text`, used to prove the resolved
    /// function offset lands on code rather than anywhere plausible.
    private func textRange(in machOFile: MachOFile) throws -> Range<Int> {
        let section = try #require(
            machOFile.sections.first(where: { $0.sectionName == "__text" && $0.segmentName == "__TEXT" })
        )
        return section.offset ..< (section.offset + section.size)
    }

    // MARK: - Tests

    @Test func offset() async throws {
        let (machOFile, record) = try loadRecord()
        // The record itself is constant data, never code.
        #expect(!(try textRange(in: machOFile)).contains(record.offset))
        #expect(record.offset > 0)
    }

    @Test func layout() async throws {
        let (machOFile, record) = try loadRecord()
        // IRGen emits `swift.coro_func_pointer` packed as
        // { i32 relative pointer, i32 size, i64 malloc type id }; on 64-bit
        // Darwin the fields are naturally aligned, so packed and unpacked
        // coincide. A Swift struct that grew padding would misread the tail.
        #expect(MemoryLayout<CoroFunctionPointer.Layout>.size == 16)
        #expect(MemoryLayout<CoroFunctionPointer.Layout>.offset(of: \.allocationSize) == 4)
        #expect(MemoryLayout<CoroFunctionPointer.Layout>.offset(of: \.mallocTypeIdentifier) == 8)
        #expect(record.layout.function.relativeOffset != 0)

        // The whole reason the record exists: it is not the entry point, it
        // points at one.
        let functionOffset = try #require(record.resolvedDirectOffset(from: \.function))
        #expect(functionOffset != record.offset)
        #expect((try textRange(in: machOFile)).contains(functionOffset))
        #expect(functionOffset == record.offset + Int(record.layout.function.relativeOffset))

        // The frame size a caller must allocate before entering the
        // coroutine — the fact that cannot be recovered from the entry point,
        // which is why callers are handed this record instead.
        #expect(record.layout.allocationSize > 0)
        #expect(record.layout.allocationSize % 8 == 0, "a coroutine frame is word-sized")
    }

    /// The `ReadingContext` leg reports the same location as a context
    /// address (a file offset for `MachOContext`).
    @Test func functionAddress() async throws {
        let (machOFile, record) = try loadRecord()
        let context = MachOContext(machOFile)
        let address = try #require(try record.functionAddress(in: context))
        #expect(Int(address) == record.resolvedDirectOffset(from: \.function))
    }
}
