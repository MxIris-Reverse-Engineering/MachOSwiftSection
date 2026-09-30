import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
import SwiftInspection
@testable import MachOTestingSupport

/// The dump path's rendering of a class the source renamed for the
/// Objective-C runtime (evolution proposal `objc-custom-class-name`): the
/// attribute the interface prints, on the line above the class, and — the
/// class's ObjC method table now being found — the ancestor chain and the
/// member annotations every `_TtC…` class already had.
@Suite(.serialized, ExclusiveImageAccess(RenamedObjCClassFixture.moduleName))
struct CustomObjCClassNameDumpTests {
    private func dump(classNamed name: String) async throws -> String {
        let machOFile = try RenamedObjCClassFixture.machOFile(.full)
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: try RenamedObjCClassFixture.dependencySearchPaths()), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor, try classDescriptor.name(in: machOFile.context) == name else { continue }
            let classType = try Class(descriptor: classDescriptor, in: machOFile.context)
            return try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        }
        Issue.record("fixture is missing the class \(name)")
        return ""
    }

    @Test func renamedClassDumpCarriesTheAttributeAndItsObjCFacts() async throws {
        let output = try await dump(classNamed: "RenamedWidget")
        let moduleName = RenamedObjCClassFixture.moduleName
        #expect(output.hasPrefix("@objc(RCFRenamedWidget)\nclass \(moduleName).RenamedWidget: NSObject {\n    // ObjC ancestor chain: NSObject\n"), "\(output)")
        #expect(output.contains("description.getter : Swift.String // overrides -[NSObject description]"), "\(output)")
        // The member's own selector, under the name the runtime knows the class by.
        #expect(output.contains("poke() -> () // @objc -[RCFRenamedWidget poke] (To thunk symbol at the IMP)"), "\(output)")
    }

    @Test func nativeClassDumpSpellsTheRuntimeNameAttribute() async throws {
        let output = try await dump(classNamed: "NativeRoot")
        #expect(output.hasPrefix("@_objcRuntimeName(RCFNativeRoot)\nclass \(RenamedObjCClassFixture.moduleName).NativeRoot {"), "\(output)")
    }

    @Test func classThatIsNotRenamedCarriesNoAttribute() async throws {
        let output = try await dump(classNamed: "PlainWidget")
        #expect(output.hasPrefix("class \(RenamedObjCClassFixture.moduleName).PlainWidget: NSObject {"), "\(output)")
    }
}
