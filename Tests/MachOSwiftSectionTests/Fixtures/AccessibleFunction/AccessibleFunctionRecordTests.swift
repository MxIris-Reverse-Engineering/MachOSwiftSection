import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AccessibleFunctionRecord`.
///
/// `SymbolTestsCore`'s `__swift5_acfuncs` section holds four records, all
/// from `DistributedActors` — distributed actor targets are the only feature
/// emitting them today. Two are picked: a non-generic target, whose generic
/// environment pointer is null, and the one generic target, whose is not, so
/// the nullable pointer is exercised in both states.
@Suite
final class AccessibleFunctionRecordTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AccessibleFunctionRecord"
    static var registeredTestMethodNames: Set<String> {
        AccessibleFunctionRecordBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let label: String
        let file: AccessibleFunctionRecord
        let image: AccessibleFunctionRecord
        let expected: AccessibleFunctionRecordBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        [
            Carrier(
                label: "nonGeneric",
                file: try BaselineFixturePicker.accessibleFunctionRecord_nonGeneric(in: machOFile),
                image: try BaselineFixturePicker.accessibleFunctionRecord_nonGeneric(in: machOImage),
                expected: AccessibleFunctionRecordBaseline.nonGeneric
            ),
            Carrier(
                label: "generic",
                file: try BaselineFixturePicker.accessibleFunctionRecord_generic(in: machOFile),
                image: try BaselineFixturePicker.accessibleFunctionRecord_generic(in: machOImage),
                expected: AccessibleFunctionRecordBaseline.generic
            ),
        ]
    }

    @Test func offset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.offset },
                image: { carrier.image.offset }
            )
            #expect(result == carrier.expected.offset, "\(carrier.label)")
        }

        // The section is a flat, gapless array: consecutive records are
        // exactly one layout apart. If that stopped holding, the reader would
        // be slicing the section wrong and every other assertion here would
        // be reading a shifted record.
        let records = try BaselineFixturePicker.accessibleFunctionRecords(in: machOFile)
        #expect(records.count == AccessibleFunctionRecordBaseline.recordCount)
        for (earlier, later) in zip(records, records.dropFirst()) {
            #expect(later.offset - earlier.offset == MemoryLayout<AccessibleFunctionRecord.Layout>.size)
        }
    }

    @Test func layout() async throws {
        for carrier in try allCarriers() {
            let flagsRaw = try acrossAllReaders(
                file: { carrier.file.layout.flags.rawValue },
                image: { carrier.image.layout.flags.rawValue }
            )
            #expect(flagsRaw == carrier.expected.flagsRawValue, "\(carrier.label)")
        }
        // Four relative pointers plus a flag word, no padding.
        #expect(MemoryLayout<AccessibleFunctionRecord.Layout>.size == 20)
    }

    @Test func flags() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.flags.rawValue },
                image: { carrier.image.flags.rawValue }
            )
            #expect(result == carrier.expected.flagsRawValue, "\(carrier.label)")
        }
    }

    @Test func isDistributed() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.isDistributed },
                image: { carrier.image.isDistributed }
            )
            #expect(result == carrier.expected.isDistributed, "\(carrier.label)")
        }
    }

    /// The lookup key: the string a remote call carries, which
    /// `swift_findAccessibleFunction` matches against.
    @Test func name() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.name(in: machOFile) },
                image: { try carrier.image.name(in: machOImage) },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).name() }
            )
            #expect(result == carrier.expected.name, "\(carrier.label)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.name(in: fileContext) },
                image: { try carrier.image.name(in: imageContext) }
            )
            #expect(fromContext == carrier.expected.name, "\(carrier.label)")
        }
    }

    /// The mangled Swift type that says what the abstracted entry point's
    /// arguments mean. Live payloads are not pinned as literals (same rule as
    /// `FieldRecordBaseline`); what is asserted is presence and cross-reader
    /// agreement.
    @Test func functionType() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { try carrier.file.functionType(in: machOFile).rawString },
                image: { try carrier.image.functionType(in: machOImage).rawString },
                inProcess: { try carrier.image.asPointerWrapper(in: self.machOImage).functionType().rawString }
            )
            #expect(!result.isEmpty == carrier.expected.hasFunctionType, "\(carrier.label)")

            let fromContext = try acrossAllContexts(
                file: { try carrier.file.functionType(in: fileContext).rawString },
                image: { try carrier.image.functionType(in: imageContext).rawString }
            )
            #expect(fromContext == result, "\(carrier.label)")
        }
    }

    @Test func genericEnvironmentOffset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.genericEnvironmentOffset },
                image: { carrier.image.genericEnvironmentOffset }
            )
            #expect(result == carrier.expected.genericEnvironmentOffset, "\(carrier.label)")
        }

        // The carriers are only worth having as a pair if they genuinely
        // differ in this one respect.
        let carriers = try allCarriers()
        #expect(carriers.filter { $0.file.genericEnvironmentOffset == nil }.count == 1)
    }

    @Test func genericEnvironment() async throws {
        for carrier in try allCarriers() {
            let resolvedOffset = try acrossAllReaders(
                file: { try carrier.file.genericEnvironment(in: machOFile)?.offset },
                image: { try carrier.image.genericEnvironment(in: machOImage)?.offset }
            )
            #expect(resolvedOffset == carrier.expected.genericEnvironmentOffset, "\(carrier.label)")
        }
    }

    /// Pure relative-pointer arithmetic, so identical across readers.
    @Test func functionOffset() async throws {
        for carrier in try allCarriers() {
            let result = try acrossAllReaders(
                file: { carrier.file.functionOffset },
                image: { carrier.image.functionOffset }
            )
            #expect(result == carrier.expected.functionOffset, "\(carrier.label)")
        }
    }

    @Test func functionAddress() async throws {
        for carrier in try allCarriers() {
            let fromContext = try acrossAllContexts(
                file: { try carrier.file.functionAddress(in: fileContext).map { Int($0) } },
                image: { try carrier.image.functionAddress(in: imageContext).map { Int($0) } }
            )
            #expect(fromContext == carrier.expected.functionOffset, "\(carrier.label)")
        }
    }

    /// A distributed target is `async`, so the record's `Function` does NOT
    /// point at code either: it points at that function's async function
    /// pointer record, which points at the code. Two hops, and this Suite
    /// plus `AsyncFunctionPointerTests` between them cover both.
    @Test func functionPointsAtAnAsyncRecordNotAtCode() async throws {
        for carrier in try allCarriers() {
            let functionOffset = try #require(carrier.file.functionOffset, "\(carrier.label)")
            let asyncRecord = try AsyncFunctionPointer.resolve(from: functionOffset, in: machOFile)
            let entryPoint = try #require(asyncRecord.functionOffset, "\(carrier.label)")
            #expect(entryPoint != functionOffset, "\(carrier.label)")
            #expect(asyncRecord.expectedContextSize > 0, "\(carrier.label)")
        }
    }
}
