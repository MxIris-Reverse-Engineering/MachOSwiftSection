import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import SwiftDeclarationRendering
import SwiftInspection
import SwiftThunkAnalysis
@testable import MachOTestingSupport

/// The dump path's rendering of the ObjC member facts (evolution proposals
/// `objc-ancestor-override-recovery` and `objc-member-selector-recovery`):
/// the ancestor chain as a comment under the class, `overrides -[Ancestor
/// selector]` on every member line tied to an inherited selector, and `@objc
/// -[Class selector]` on every other member line the ObjC method table ties.
/// From the fixture FILE the clang class's bound `NSObject` is followed into
/// the running system's cache (evolution proposal
/// `objc-ancestor-dependency-closure`); one test installs a resolver over no
/// images to pin the chain comment of a bind nothing answers.
@Suite(.serialized, ExclusiveImageAccess(ObjCImplementationFixture.moduleName))
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

    /// Runs `body` with a resolver over the fixture's whole world (the
    /// category dylib, the host's cache) registered for the file.
    private func withFixtureWorld<Result>(for machOFile: MachOFile, _ body: () async throws -> Result) async throws -> Result {
        ObjCAncestorResolverStore.shared.register(ObjCAncestorResolver(root: machOFile, searchPaths: try ObjCImplementationFixture.dependencySearchPaths()), for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        return try await body()
    }

    @Test func swiftClassDumpNamesTheAncestorChainAndTheOverriddenSelectors() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        try await withFixtureWorld(for: machOFile) {
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftDerivedWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        let moduleName = ObjCImplementationFixture.moduleName
        // The chain — on its own line right under the header — runs through
        // the bound `NSObject`, found in the host's cache.
        #expect(output.contains(" {\n    // ObjC ancestor chain: ClangWidget → NSObject\n"))
        #expect(output.contains("ping() -> () // overrides -[ClangWidget ping]"))
        #expect(output.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount]"))
        #expect(output.contains("level.getter : Swift.Int // overrides -[ClangWidget level]"))
        #expect(output.contains("level.setter : Swift.Int // overrides -[ClangWidget setLevel:]"))
        #expect(!output.contains("notAnOverride() -> () // overrides"))
        #expect(output.contains("description.getter : Swift.String // overrides -[NSObject description]"))
        // The category dylib's method, found through the closure's files.
        #expect(output.contains("noteValue(forKeyPath: Swift.String, of: Any) -> () // overrides -[NSObject noteValueForKeyPath:ofObject:]"))
        // Every other member of the method table names its selector.
        #expect(output.contains("notAnOverride() -> () // @objc -[\(moduleName).SwiftDerivedWidget notAnOverride] (To thunk symbol at the IMP)"))
        // The chain being complete, the explicit-selector verdict is given.
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget pokeUsingForce:], explicit selector (To thunk symbol at the IMP)"))
        #expect(output.contains("alias.getter : Swift.Int // @objc -[\(moduleName).SwiftDerivedWidget customLevel], explicit selector (To thunk symbol at the IMP)"))
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget moveToWindow:] (To thunk symbol at the IMP)"))
        #expect(!output.contains("moveToWindow:], explicit selector"))
        #expect(output.contains("// @objc -[\(moduleName).SwiftDerivedWidget fetchAndReturnError:] (To thunk symbol at the IMP)"))
        // A witness's inherited selector is not explicit.
        #expect(output.contains("priority.getter : Swift.Int // @objc -[\(moduleName).SwiftDerivedWidget observerPriority] (To thunk symbol at the IMP)"))
        #expect(!output.contains("observerPriority], explicit selector"))
        // Not in the method table at all.
        #expect(!output.contains("typeName() -> Swift.String // @objc"))
        }
    }

    @Test func swiftAncestorsPrintByTheirQualifiedName() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftGrandchildWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        let moduleName = ObjCImplementationFixture.moduleName
        // The Swift ancestor's `class_ro_t` name is its mangled runtime name;
        // the comment spells it the way the rest of the dump does.
        #expect(output.contains("// ObjC ancestor chain: \(moduleName).SwiftDerivedWidget → ClangWidget → NSObject\n"))
        #expect(output.contains("dynamicHook() -> () // overrides -[\(moduleName).SwiftDerivedWidget dynamicHook] (To thunk symbol at the IMP)"))
    }

    /// A bind no dependency image answers — here, a resolver over no images
    /// standing in for a file whose linked images are nowhere on the host —
    /// is spelled out in the chain comment, and no explicit selector is
    /// claimed past it.
    @Test func fileWithoutDependencyImagesReportsTheBoundChain() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        ObjCAncestorResolverStore.shared.register(.empty, for: machOFile)
        defer { ObjCAncestorResolverStore.shared.remove(for: machOFile) }
        let classType = try Class(descriptor: try classDescriptor(named: "SwiftGrandchildWidget", in: machOFile), in: machOFile)
        let output = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
        let moduleName = ObjCImplementationFixture.moduleName
        #expect(output.contains("// ObjC ancestor chain: \(moduleName).SwiftDerivedWidget → ClangWidget → NSObject (bound; chain not resolvable offline)"))
        #expect(!output.contains("explicit selector"))
    }

    @Test func implementationClassDumpNamesTheOverriddenAncestor() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.full)
        let implementationClass = try #require(ObjCImplementationClass.all(in: machOFile).first { $0.facts.className == "DerivedImplementationWidget" })
        let output = try await implementationClass.dump(using: .demangleOptions(.test), in: machOFile).string
        #expect(output.contains("// ObjC ancestor chain: ClangWidget → NSObject\n"))
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

    /// Bodies the optimizer inlined into their thunks tie through nothing;
    /// by default the member lines carry no ObjC comment and the
    /// `@implementation` method lines say so. With the image's recovery
    /// options asking for the name-only tier, both dumpers mark the
    /// overrides — and name the evidence for what it is.
    @Test func inlinedOverridesAreTiedByNameOnlyWhenAsked() async throws {
        let machOFile = try ObjCImplementationFixture.machOFile(.optimizedStripped)
        let moduleName = ObjCImplementationFixture.moduleName
        try await withFixtureWorld(for: machOFile) {
            let classType = try Class(descriptor: try classDescriptor(named: "SwiftDerivedWidget", in: machOFile), in: machOFile)
            let implementationClass = try #require(ObjCImplementationClass.all(in: machOFile).first { $0.facts.className == "DerivedImplementationWidget" })

            let silent = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
            #expect(silent.contains("// ObjC ancestor chain: ClangWidget → NSObject\n"))
            #expect(!silent.contains("ping() -> () // overrides"))
            #expect(!silent.contains("selector name, no symbol evidence"))
            let silentImplementation = try await implementationClass.dump(using: .demangleOptions(.test), in: machOFile).string
            let silentPing = try #require(silentImplementation.split(separator: "\n").first { $0.contains("-[DerivedImplementationWidget ping]") })
            #expect(silentPing.hasSuffix(", overrides ClangWidget (no Swift member tied to this IMP)"))

            ObjCMemberRecoveryOptionsStore.shared.register(ObjCMemberRecoveryOptions(infersOverridesFromSelectorNames: true), for: machOFile)
            defer { ObjCMemberRecoveryOptionsStore.shared.remove(for: machOFile) }
            let inferred = try await classType.dump(using: .demangleOptions(.test), in: machOFile).string
            #expect(inferred.contains("ping() -> () // overrides -[ClangWidget ping] (selector name, no symbol evidence)"))
            #expect(inferred.contains("pingCount() -> Swift.Int // overrides +[ClangWidget pingCount] (selector name, no symbol evidence)"))
            #expect(inferred.contains("level.getter : Swift.Int // overrides -[ClangWidget level] (selector name, no symbol evidence)"))
            #expect(inferred.contains("level.setter : Swift.Int // overrides -[ClangWidget setLevel:] (selector name, no symbol evidence)"))
            #expect(inferred.contains("description.getter : Swift.String // overrides -[NSObject description] (selector name, no symbol evidence)"))
            // Not an override: the name-only tier never touches it.
            #expect(!inferred.contains("notAnOverride() -> () // @objc"))
            #expect(!inferred.contains("\(moduleName).SwiftDerivedWidget pokeUsingForce:]"))
            let inferredImplementation = try await implementationClass.dump(using: .demangleOptions(.test), in: machOFile).string
            let inferredPing = try #require(inferredImplementation.split(separator: "\n").first { $0.contains("-[DerivedImplementationWidget ping]") })
            #expect(inferredPing.hasSuffix(", overrides ClangWidget (selector name, no symbol evidence)"))
            #expect(inferredImplementation.contains("ping() -> () // overrides -[ClangWidget ping] (selector name, no symbol evidence)"))
            let poke = try #require(inferredImplementation.split(separator: "\n").first { $0.contains("-[DerivedImplementationWidget poke]") })
            #expect(poke.hasSuffix("no Swift member tied to this IMP"))
        }
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
