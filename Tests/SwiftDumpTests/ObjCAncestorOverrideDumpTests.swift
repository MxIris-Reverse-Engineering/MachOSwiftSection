import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
import SwiftThunkAnalysis
@testable import MachOTestingSupport

/// The dump path's rendering of the ObjC-ancestor override facts (evolution
/// proposal `objc-ancestor-override-recovery`): the ancestor chain as a
/// comment under the class, and `overrides -[Ancestor selector]` on every
/// member line whose `To` thunk answers to an inherited selector.
@Suite(.serialized)
struct ObjCAncestorOverrideDumpTests {
    private func classDescriptor(named name: String, in machOFile: MachOFile) throws -> ClassDescriptor {
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            guard try classDescriptor.name(in: machOFile) == name else { continue }
            return classDescriptor
        }
        Issue.record("fixture is missing the class \(name)")
        throw ObjCImplementationFixture.CompilationError(step: "lookup", diagnostics: "class \(name) not found")
    }

    @Test func swiftClassDumpNamesTheAncestorChainAndTheOverriddenSelectors() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftDerivedWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        // From the file the clang class's superclass is a bind: the chain says
        // so — on its own line right under the header.
        #expect(output.contains(" {\n    // ObjC ancestor chain: ClangWidget → NSObject (bound; chain not resolvable offline)\n"))
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping]"))
        #expect(output.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount]"))
        #expect(output.contains("level.getter : Swift.Int // overrides -[ClangWidget level]"))
        #expect(output.contains("level.setter : Swift.Int // overrides -[ClangWidget setLevel:]"))
        #expect(!output.contains("notAnOverride() -> () // overrides"))
        #expect(!output.contains("description.getter : Swift.String // overrides"))
    }

    @Test func swiftAncestorsPrintByTheirQualifiedName() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftGrandchildWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        let moduleName = ObjCImplementationFixture.moduleName
        // The Swift ancestor's `class_ro_t` name is its mangled runtime name;
        // the comment spells it the way the rest of the dump does.
        #expect(output.contains("// ObjC ancestor chain: \(moduleName).SwiftDerivedWidget → ClangWidget → NSObject (bound; chain not resolvable offline)"))
        #expect(output.contains("dynamicHook() -> () // overrides -[\(moduleName).SwiftDerivedWidget dynamicHook] (To thunk symbol at the IMP)"))
    }

    @Test func implementationClassDumpNamesTheOverriddenAncestor() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let implementationClass = try #require(ObjCImplementationClass.all(in: machOFile).first { $0.facts.className == "DerivedImplementationWidget" })
        let output = try await implementationClass.dump(using: .demangleOptions(.test), in: machOFile).string
        #expect(output.contains("// ObjC ancestor chain: ClangWidget → NSObject (bound; chain not resolvable offline)"))
        let lines = output.split(separator: "\n").map(String.init)
        let ping = try #require(lines.first { $0.contains("-[DerivedImplementationWidget ping]") })
        #expect(ping.hasSuffix(", overrides ClangWidget"))
        #expect(ping.contains("To, overrides ClangWidget"))
        let pingCount = try #require(lines.first { $0.contains("+[DerivedImplementationWidget pingCount]") })
        #expect(pingCount.hasSuffix(", overrides ClangWidget"))
        let poke = try #require(lines.first { $0.contains("-[DerivedImplementationWidget poke]") })
        #expect(!poke.contains("overrides"))
        // The Swift member listing carries the same fact per symbol.
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping]"))
        #expect(output.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount]"))
    }
}
