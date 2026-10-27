import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
@testable import MachOTestingSupport

/// The dump path's listing of the members an image keeps only as their
/// `@objc` thunk (evolution proposal `thunk-only-objc-members`): the
/// optimizer inlined the Swift body into the thunk and deleted the Swift
/// entry point, so the dump, which lists a class's members from their
/// symbols, listed none of them. They now get a section of their own after
/// the member symbols, printed from the thunk, with the ObjC method table's
/// facts where the class has a table.
@Suite(.serialized, ExclusiveImageAccess(ThunkOnlyMemberFixture.moduleName))
struct ThunkOnlyObjCMemberDumpTests {
    private func classDescriptor(named name: String, in machOFile: MachOFile) throws -> ClassDescriptor {
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            guard try classDescriptor.name(in: machOFile.context) == name else { continue }
            return classDescriptor
        }
        Issue.record("fixture is missing the class \(name)")
        throw ThunkOnlyMemberFixture.CompilationError(step: "lookup", diagnostics: "class \(name) not found")
    }

    private func dump(ofClassNamed name: String, in variant: ThunkOnlyMemberFixture.Variant) async throws -> String {
        let machOFile = try ThunkOnlyMemberFixture.machOFile(variant)
        let classType = try Class(descriptor: try classDescriptor(named: name, in: machOFile), in: machOFile.context)
        return try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
    }

    @Test func thunkOnlyMembersAreListedFromTheirThunks() async throws {
        let output = try await dump(ofClassNamed: "ThunkOnlyWidget", in: .wholeModuleOptimized)
        let moduleName = ThunkOnlyMemberFixture.moduleName
        #expect(output.contains("/* [ObjC Thunk] Function */"), "\(output)")
        #expect(output.contains("@objc \(moduleName).ThunkOnlyWidget.isEqual(Any?) -> Swift.Bool // overrides -[NSObject isEqual:] (To thunk symbol at the IMP)"), "\(output)")
        #expect(output.contains("@objc \(moduleName).ThunkOnlyWidget.handleTick(Any?) -> () // @objc -[\(moduleName).ThunkOnlyWidget handleTick:] (To thunk symbol at the IMP)"), "\(output)")
        #expect(output.contains("/* [ObjC Thunk] Variable */"), "\(output)")
        #expect(output.contains("@objc \(moduleName).ThunkOnlyWidget.description.getter : Swift.String // overrides -[NSObject description] (To thunk symbol at the IMP)"), "\(output)")
        #expect(output.contains("/* [ObjC Thunk] Constructor */"), "\(output)")
        #expect(output.contains("@objc \(moduleName).ThunkOnlyWidget.init() -> \(moduleName).ThunkOnlyWidget // overrides -[NSObject init] (To thunk symbol at the IMP)"), "\(output)")
    }

    /// The unoptimized build keeps every Swift entry point, so no thunk is a
    /// member's only symbol and the section is absent.
    @Test func membersWithASwiftEntryPointAreNotListedAgain() async throws {
        let output = try await dump(ofClassNamed: "ThunkOnlyWidget", in: .unoptimized)
        #expect(!output.contains("[ObjC Thunk]"), "\(output)")
    }

    /// A generic class has no static class object; its ObjC method table is
    /// the template in its generic metadata pattern (evolution proposal
    /// `objc-classes-without-class-objects`), so the thunk carries the same
    /// comment as a class with a class object. Its synthesized `init()` kept
    /// its initializing entry point, so its thunk is not the only symbol it
    /// has.
    @Test func genericClassThunkOnlyMembersCarryTheirObjCComment() async throws {
        let output = try await dump(ofClassNamed: "GenericThunkOnlyWidget", in: .wholeModuleOptimized)
        let moduleName = ThunkOnlyMemberFixture.moduleName
        #expect(output.contains("@objc \(moduleName).GenericThunkOnlyWidget.description.getter : Swift.String // overrides -[NSObject description] (To thunk symbol at the IMP)"), "\(output)")
        #expect(!output.contains("/* [ObjC Thunk] Constructor */"), "\(output)")
    }
}
