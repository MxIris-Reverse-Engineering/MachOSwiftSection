import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A `ReadingContext` over a file has to read a pointer slot the way dyld
/// leaves it at load time, not the way the file stores it: a rebased slot
/// stores a chained-fixup encoding, a bound slot names a symbol in another
/// image. The Mach-O reading forms always consulted the fixup tables; the
/// context forms — now the only implementation — must too.
@Suite
final class ReadingContextRelocationTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Every rebased pointer slot in the fixture, paired with the target
    /// dyld writes there.
    private func rebasedSlots() throws -> [(offset: Int, target: UInt64)] {
        let chainedFixups = try #require(machOFile.dyldChainedFixups)
        let startsInImage = try #require(chainedFixups.startsInImage)
        var slots: [(offset: Int, target: UInt64)] = []
        for startsInSegment in chainedFixups.startsInSegments(of: startsInImage) {
            for fixupPointer in chainedFixups.pointers(of: startsInSegment, in: machOFile) where fixupPointer.fixupInfo.rebase != nil {
                guard let target = machOFile.resolveRebase(fileOffset: fixupPointer.offset) else { continue }
                slots.append((fixupPointer.offset, target))
            }
        }
        return slots
    }

    @Test func aPointerReadFromAFileIsTheRebaseTarget() throws {
        let slots = try rebasedSlots()
        try #require(!slots.isEmpty)
        // The stored bytes of a chained fixup carry the chain link and format
        // bits; if they happened to equal the target everywhere, this test
        // could not tell a rebase-aware read from a raw one.
        let someSlotStoresAnEncoding = try slots.contains { slot in
            let storedBytes: UInt64 = try machOFile.readElement(offset: slot.offset)
            return storedBytes != slot.target
        }
        try #require(someSlotStoresAnEncoding)

        let misreadSlots = try slots.filter { slot in
            try Pointer<AnyResolvable>.resolve(at: slot.offset, in: fileContext).address != slot.target
        }
        #expect(misreadSlots.isEmpty, "\(misreadSlots.count) of \(slots.count) rebased slots read as their stored bytes")
    }

    /// The runtime reads a stored address whose only set bits are tag bits
    /// as a null pointer, and so do the Mach-O and pointer forms; the
    /// in-process context used to follow it and throw.
    @Test func aStoredAddressOfOnlyTagBitsIsANullElement() throws {
        let pointer = SymbolOrElementPointer<ContextDescriptorWrapper?>.address(0x8000_0000_0000_0000)
        let resolved = try pointer.resolve(in: inProcessContext)
        guard case .element(let element) = resolved else {
            Issue.record("resolved to \(resolved) instead of an element")
            return
        }
        #expect(element == nil)
    }
}

/// Where the standalone iOS 26.5 simulator runtime keeps
/// `libswiftSynchronization`: the last runtime whose libraries are separate
/// files, so a cross-image reference is a bind rather than a rebase.
enum StandaloneSimulatorRuntimeLibraries {
    static let synchronizationPath: String = {
        let swiftUIPath = MachOFileName.iOS_26_5_Simulator_SwiftUI.rawValue
        let runtimeRoot = swiftUIPath.dropLast("/System/Library/Frameworks/SwiftUI.framework/SwiftUI".count)
        return runtimeRoot + "/usr/lib/swift/libswiftSynchronization.dylib"
    }()

    static var hasSynchronization: Bool {
        FileManager.default.fileExists(atPath: synchronizationPath)
    }
}

@Suite(.enabled(if: StandaloneSimulatorRuntimeLibraries.hasSynchronization))
struct BoundTypeMetadataRecordTests {
    /// `libswiftSynchronization` registers a type record for `libswiftCore`'s
    /// `Swift.Optional`. In a standalone file that record is indirect and its
    /// slot is a bind: there is no descriptor in this image to read, so the
    /// record resolves to none instead of reading the bind's encoding as an
    /// address.
    @Test func anIndirectRecordOfAStandaloneLibraryResolvesToNoDescriptor() throws {
        guard case .machO(let library) = try File.loadFromFile(url: URL(fileURLWithPath: StandaloneSimulatorRuntimeLibraries.synchronizationPath)) else {
            Issue.record("expected a thin dylib at \(StandaloneSimulatorRuntimeLibraries.synchronizationPath)")
            return
        }
        let section = try library.section(for: MachOSwiftSectionName.__swift5_types)
        let records: [TypeMetadataRecord] = try library.readWrapperElements(
            offset: section.offset,
            numberOfElements: section.size / TypeMetadataRecord.layoutSize
        )
        let indirectRecords = records.filter { $0.typeKind == .indirectTypeDescriptor }
        try #require(!indirectRecords.isEmpty)
        for record in indirectRecords {
            #expect(try record.contextDescriptor(in: library.context) == nil)
        }
    }
}
