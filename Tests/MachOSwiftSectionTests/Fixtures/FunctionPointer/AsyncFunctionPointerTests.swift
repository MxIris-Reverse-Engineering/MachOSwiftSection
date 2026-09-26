import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AsyncFunctionPointer`.
///
/// The record sits in no `__swift5_*` section, so the three carriers are
/// picked by `…Tu` symbol name: a top-level `async` function, an `async`
/// class method a vtable slot points at, and a distributed thunk. Every
/// assertion runs across both readers, because everything the record exposes
/// is either a raw word or pure relative-pointer arithmetic.
@Suite
final class AsyncFunctionPointerTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AsyncFunctionPointer"
    static var registeredTestMethodNames: Set<String> {
        AsyncFunctionPointerBaseline.registeredTestMethodNames
    }

    private struct Carrier {
        let label: String
        let file: AsyncFunctionPointer
        let image: AsyncFunctionPointer
        let expected: AsyncFunctionPointerBaseline.Entry
    }

    private func allCarriers() throws -> [Carrier] {
        let fileRecords = try AsyncFunctionPointerFixtureRecords(in: machOFile)
        let imageRecords = try AsyncFunctionPointerFixtureRecords(in: machOImage)
        return [
            Carrier(
                label: "globalFunction",
                file: fileRecords.globalFunction,
                image: imageRecords.globalFunction,
                expected: AsyncFunctionPointerBaseline.globalFunction
            ),
            Carrier(
                label: "vtableMethod",
                file: fileRecords.vtableMethod,
                image: imageRecords.vtableMethod,
                expected: AsyncFunctionPointerBaseline.vtableMethod
            ),
            Carrier(
                label: "distributedThunk",
                file: fileRecords.distributedThunk,
                image: imageRecords.distributedThunk,
                expected: AsyncFunctionPointerBaseline.distributedThunk
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
    }

    @Test func layout() async throws {
        for carrier in try allCarriers() {
            let relativeOffset = try acrossAllReaders(
                file: { carrier.file.layout.function.relativeOffset },
                image: { carrier.image.layout.function.relativeOffset }
            )
            #expect(Int(relativeOffset) == carrier.expected.functionOffset.map { $0 - carrier.expected.offset }, "\(carrier.label)")

            let contextSize = try acrossAllReaders(
                file: { carrier.file.layout.expectedContextSize },
                image: { carrier.image.layout.expectedContextSize }
            )
            #expect(contextSize == carrier.expected.expectedContextSize, "\(carrier.label)")
        }
        // The whole record is two words; a Swift struct that grew padding
        // would silently shift every read that follows it.
        #expect(MemoryLayout<AsyncFunctionPointer.Layout>.size == 8)

        // Resolving the function pointer is pure arithmetic, so it is
        // identical across readers and pinned as a literal.
        for carrier in try allCarriers() {
            let functionOffset = try acrossAllReaders(
                file: { carrier.file.resolvedDirectOffset(from: \.function) },
                image: { carrier.image.resolvedDirectOffset(from: \.function) }
            )
            #expect(functionOffset == carrier.expected.functionOffset, "\(carrier.label)")
            // The record never points at itself: the whole reason it exists
            // is that it is NOT the entry point.
            #expect(functionOffset != carrier.expected.offset, "\(carrier.label)")
        }

        // The context size is what the record is FOR, and the reason the
        // three carriers are not interchangeable: a distributed thunk's frame
        // is an order of magnitude larger than a plain async function's.
        let carriers = try allCarriers()
        let plain = try #require(carriers.first(where: { $0.label == "globalFunction" }))
        let thunk = try #require(carriers.first(where: { $0.label == "distributedThunk" }))
        #expect(
            thunk.file.layout.expectedContextSize > plain.file.layout.expectedContextSize,
            "the fixture must keep carrying two genuinely different context sizes"
        )
    }

    /// The `ReadingContext` leg reports the same location as a context
    /// address (a file offset for `MachOContext`).
    @Test func functionAddress() async throws {
        for carrier in try allCarriers() {
            let fromContext = try acrossAllContexts(
                file: { try carrier.file.functionAddress(in: fileContext).map { Int($0) } },
                image: { try carrier.image.functionAddress(in: imageContext).map { Int($0) } }
            )
            #expect(fromContext == carrier.expected.functionOffset, "\(carrier.label)")
        }
    }

    /// Why this record is worth modelling at all: a method descriptor's
    /// implementation pointer for an `async` method lands HERE, not on the
    /// machine code. IRGen substitutes the record's address wherever a
    /// normal function's would go (`GenMeta.cpp`, the `impl->isAsync()`
    /// branch), so a consumer reading `implementationOffset` and calling it
    /// "the implementation" is one hop short.
    @Test func vtableMethodDescriptorPointsAtTheRecordNotTheCode() async throws {
        let classDescriptor = try BaselineFixturePicker.class_VTableBaseTest(in: machOFile)
        let vtableClass = try Class(descriptor: classDescriptor, in: machOFile)
        let record = try AsyncFunctionPointerFixtureRecords(in: machOFile).vtableMethod

        let descriptorsPointingAtTheRecord = vtableClass.methodDescriptors.filter {
            $0.implementationOffset == record.offset
        }
        #expect(
            descriptorsPointingAtTheRecord.count == 1,
            "exactly one vtable slot of VTableBaseTest should carry the async method's record address"
        )
        #expect(record.resolvedDirectOffset(from: \.function) != record.offset)
    }
}
