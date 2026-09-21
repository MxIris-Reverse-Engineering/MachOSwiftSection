import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
import SwiftThunkAnalysis
@testable import MachOTestingSupport

/// The dump path's rendering of the ObjC member facts (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`):
/// the ancestor chain as a comment under the class, `overrides -[Ancestor
/// selector]` on every member line tied to an inherited selector, and `@objc
/// -[Class selector]` on every other member line the ObjC method table ties.
@Suite(.serialized)
struct ObjCMemberDumpTests {
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
        let moduleName = ObjCImplementationFixture.moduleName
        // From the file the clang class's superclass is a bind: the chain says
        // so — on its own line right under the header.
        #expect(output.contains(" {\n    // ObjC ancestor chain: ClangWidget → NSObject (bound; chain not resolvable offline)\n"))
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping]"))
        #expect(output.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount]"))
        #expect(output.contains("level.getter : Swift.Int // overrides -[ClangWidget level]"))
        #expect(output.contains("level.setter : Swift.Int // overrides -[ClangWidget setLevel:]"))
        #expect(!output.contains("notAnOverride() -> () // overrides"))
        #expect(!output.contains("description.getter : Swift.String // overrides"))
        // Every other member of the method table names its selector.
        #expect(output.contains("notAnOverride() -> () // @objc -[\(moduleName).SwiftDerivedWidget notAnOverride] (To thunk symbol at the IMP)"))
        // From the FILE the chain ends at the bound `NSObject`: the selector
        // is named, the explicit-selector verdict withheld.
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget pokeUsingForce:] (To thunk symbol at the IMP)"))
        #expect(output.contains("alias.getter : Swift.Int // @objc -[\(moduleName).SwiftDerivedWidget customLevel] (To thunk symbol at the IMP)"))
        #expect(!output.contains("explicit selector"))
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget moveToWindow:] (To thunk symbol at the IMP)"))
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget fetchAndReturnError:] (To thunk symbol at the IMP)"))
        // A witness's inherited selector is not explicit.
        #expect(output.contains("priority.getter : Swift.Int // @objc -[\(moduleName).SwiftDerivedWidget observerPriority] (To thunk symbol at the IMP)"))
        #expect(!output.contains("observerPriority], explicit selector"))
        // Not in the method table at all.
        #expect(!output.contains("typeName() -> Swift.String // @objc"))
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
        #expect(!poke.contains("no Swift member tied"))
        // The Swift member listing carries the same facts per symbol.
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping]"))
        #expect(output.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount]"))
        #expect(output.contains("poke() -> () // @objc -[DerivedImplementationWidget poke] (To thunk symbol at the IMP)"))
    }

    /// In-process the chain reaches `NSObject` and the protocol is readable,
    /// so the explicit selectors are judged.
    @Test func inProcessDumpNamesTheExplicitSelectors() async throws {
        let libraryURL = try ObjCImplementationFixture.libraryURL(.full)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        let machOImage = try #require(MachOImage(name: libraryURL.deletingPathExtension().lastPathComponent), "the fixture dylib did not load in-process")
        var descriptor: ClassDescriptor?
        for typeContextDescriptor in try machOImage.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor, try classDescriptor.name(in: machOImage) == "SwiftDerivedWidget" else { continue }
            descriptor = classDescriptor
        }
        let classType = try Class(descriptor: try #require(descriptor), in: machOImage)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOImage).string
        let moduleName = ObjCImplementationFixture.moduleName
        #expect(output.contains("// ObjC ancestor chain: ClangWidget → NSObject\n"))
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget pokeUsingForce:], explicit selector (To thunk symbol at the IMP)"))
        #expect(output.contains("alias.getter : Swift.Int // @objc -[\(moduleName).SwiftDerivedWidget customLevel], explicit selector"))
        #expect(output.contains("description.getter : Swift.String // overrides -[NSObject description]"))
        #expect(!output.contains("observerPriority], explicit selector"))
    }

    /// Stripped thunks — the OS-framework shape — tie through the thunk's code.
    @Test func strippedThunksStillNameTheSelector() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.strippedLocals)
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftDerivedWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        let moduleName = ObjCImplementationFixture.moduleName
        #expect(output.contains("notAnOverride() -> () // @objc -[\(moduleName).SwiftDerivedWidget notAnOverride] (the IMP's code references the implementation)"))
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping] (the IMP's code references the implementation)"))
        #expect(!output.contains("To thunk symbol at the IMP"))
    }
}
