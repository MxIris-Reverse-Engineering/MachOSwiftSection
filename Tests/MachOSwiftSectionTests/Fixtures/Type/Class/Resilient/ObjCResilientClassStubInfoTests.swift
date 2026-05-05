import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `ObjCResilientClassStubInfo`.
///
/// `ObjCResilientClassStubInfo` is the trailing-object record carrying
/// a `RelativeDirectRawPointer` to the resilient class stub. It only
/// appears when a class has `hasObjCResilientClassStub == true` —
/// i.e. ObjC interop is on, the class is non-generic, and its
/// metadata strategy is `Resilient` or `Singleton` (metadata requires
/// runtime relocation). The Suite drives the new
/// `ObjCResilientStubFixtures.ResilientObjCStubChild` (parent
/// `SymbolTestsHelper.Object`, cross-module) and asserts cross-reader
/// agreement on the discovered scalars.
@Suite
final class ObjCResilientClassStubInfoTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ObjCResilientClassStubInfo"
    static var registeredTestMethodNames: Set<String> {
        ObjCResilientClassStubInfoBaseline.registeredTestMethodNames
    }

    /// Helper: load the `ObjCResilientClassStubInfo` record from
    /// `ObjCResilientStubFixtures.ResilientObjCStubChild`.
    private func loadResilientObjCStubChildStub(
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> ObjCResilientClassStubInfo {
        let descriptor = try BaselineFixturePicker.class_ResilientObjCStubChild(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        return try required(classWrapper.objcResilientClassStubInfo)
    }

    @Test func offset() async throws {
        let fileSubject = try loadResilientObjCStubChildStub(in: machOFile)
        let imageSubject = try loadResilientObjCStubChildStub(in: machOImage)
        let result = try acrossAllReaders(
            file: { fileSubject.offset },
            image: { imageSubject.offset }
        )
        #expect(result == ObjCResilientClassStubInfoBaseline.resilientObjCStubChild.offset)
    }

    @Test func layout() async throws {
        let fileSubject = try loadResilientObjCStubChildStub(in: machOFile)
        let imageSubject = try loadResilientObjCStubChildStub(in: machOImage)
        // The relative raw pointer's relativeOffset scalar must agree
        // across readers (it's a stable file/image-relative displacement).
        let result = try acrossAllReaders(
            file: { fileSubject.layout.stub.relativeOffset },
            image: { imageSubject.layout.stub.relativeOffset }
        )
        #expect(result == ObjCResilientClassStubInfoBaseline.resilientObjCStubChild.layoutStubRelativeOffset)
    }
}
