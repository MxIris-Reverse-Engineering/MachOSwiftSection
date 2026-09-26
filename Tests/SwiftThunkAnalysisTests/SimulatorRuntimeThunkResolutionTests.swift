import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import MachOTestingSupport
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import SwiftThunkAnalysis
import SwiftDump

/// Where the simulator-runtime-gated suites below find their binaries.
///
/// A separate type on purpose: a `@Suite(.enabled(if:))` condition that
/// reads a static of the suite it decorates is a circular macro reference.
enum SimulatorRuntimeThunkFixtures {
    /// iOS 26.5: the last runtime that ships SwiftUI as a standalone file.
    static let standaloneSwiftUIPath = MachOFileName.iOS_26_5_Simulator_SwiftUI.rawValue
    static let standaloneSwiftUICorePath = MachOFileName.iOS_26_5_Simulator_SwiftUICore.rawValue
    static var hasStandaloneSwiftUI: Bool {
        FileManager.default.fileExists(atPath: standaloneSwiftUIPath) && FileManager.default.fileExists(atPath: standaloneSwiftUICorePath)
    }

    /// iOS 27.0: SwiftUI lives in the runtime's own dyld cache.
    static let simulatorCachePath = DyldSharedCachePath.iOS_27_0_Simulator.rawValue
    static var hasSimulatorCache: Bool { FileManager.default.fileExists(atPath: simulatorCachePath) }
}

/// SwiftUI as an iOS 26.5 simulator runtime ships it: a standalone Mach-O
/// whose every cross-image call is a GOT bind, read with the search paths
/// inferred from the file's own location (`RuntimeRoot`).
///
/// Measured on 2026-09-13 before this route existed: 5 unread references
/// and two branch comments naming intermediates (`_TaskModifier2` for a
/// `Body` that is `ModifiedContent<…, _TaskModifier2>`). Every expectation
/// below is what the macOS 26.6.2 shared cache — where the same thunks
/// resolve through rebases — prints for the same declarations.
@Suite(.serialized, .enabled(if: SimulatorRuntimeThunkFixtures.hasStandaloneSwiftUI))
struct SimulatorStandaloneSwiftUIThunkTests {
    private func loadSwiftUI() throws -> MachOFile {
        try load(path: SimulatorRuntimeThunkFixtures.standaloneSwiftUIPath)
    }

    private func load(path: String) throws -> MachOFile {
        switch try File.loadFromFile(url: URL(fileURLWithPath: path)) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    private func resolvedFieldTexts(ofTypeNamed typeName: String, in machOFile: MachOFile) throws -> [String: String] {
        var texts: [String: String] = [:]
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let name = try? SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default),
                  name == typeName,
                  let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile)
            else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile)
                else { continue }
                let resolvedNode = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout)
                texts[try record.fieldName(in: machOFile)] = resolvedNode.print(using: .default)
            }
        }
        return texts
    }

    /// The runtime's `libswiftSynchronization` registers a type record for
    /// `libswiftCore`'s `Swift.Optional` — an indirect record whose slot is a
    /// bind. That one record used to throw and drop every type of the
    /// image, which is why `Mutex`'s accessor could not be indexed.
    @Test func theRuntimesSynchronizationLibraryListsItsTypes() throws {
        let runtimeRoot = String(SimulatorRuntimeThunkFixtures.standaloneSwiftUIPath.dropLast("/System/Library/Frameworks/SwiftUI.framework/SwiftUI".count))
        let libraryURL = URL(fileURLWithPath: runtimeRoot + "/usr/lib/swift/libswiftSynchronization.dylib")
        guard case .machO(let library) = try File.loadFromFile(url: libraryURL) else {
            Issue.record("expected a thin dylib at \(libraryURL.path)")
            return
        }
        let typeNames = try library.swift.typeContextDescriptors.compactMap { wrapper in
            try? SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: library).print(using: .default)
        }
        #expect(typeNames.contains("Synchronization.Mutex"), "\(typeNames)")
        #expect(typeNames.count >= 10, "\(typeNames)")
    }

    /// `observedTasks`'s thunk calls a lazily specialized accessor the image
    /// carries under a local symbol; `state`'s calls `Mutex`'s accessor in
    /// `libswiftSynchronization` through a bind.
    @Test func theNoncopyableFieldsResolveToTheirTypes() throws {
        let machOFile = try loadSwiftUI()
        let schedulerFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.BGTaskSchedulerWrapper", in: machOFile)
        #expect(schedulerFields["observedTasks"] == "Synchronization.Mutex<Swift.Set<Swift.String>>")
        let lazyItemFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.Drag.LazyItem", in: machOFile)
        #expect(lazyItemFields["state"] == "Synchronization.Mutex<SwiftUI.Drag.LazyItem<A>.State>")
    }

    /// SwiftUICore's two `Mutex` fields whose thunks call a compiler-merged
    /// accessor (`…MaTm`): the real accessor arrives in `x3` from a GOT bind
    /// and the merged body only probes a cache and `blr`s it, so the type
    /// is read by following the call into that body with the caller's
    /// registers. The merged symbol's own name (`Optional<Any>`, one of the
    /// bodies folded together) must never be the answer — it once printed
    /// `Array<LayoutDirection>` for a `Mutex<Storage>` — and the field the
    /// reader reads through a local specialized accessor is asserted
    /// alongside.
    @Test func aMergedAccessorIsReadThroughItsBody() throws {
        let machOFile = try load(path: SimulatorRuntimeThunkFixtures.standaloneSwiftUICorePath)
        let settingsFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.PlatformAccessibilitySettingsDefinition", in: machOFile)
        #expect(settingsFields["cache"] == "Synchronization.Mutex<SwiftUI.PlatformAccessibilitySettingsDefinition.(Storage in _DD012B99EE4F6885B033D7D23FEF69C0)>")
        let imageCacheFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.NamedImage.Cache", in: machOFile)
        #expect(imageCacheFields["data"] == "Synchronization.Mutex<SwiftUI.NamedImage.Cache.(Data in _8E7DCD4CEB1ACDE07B249BFF4CBC75C0)>")
        let storageFields = try resolvedFieldTexts(ofTypeNamed: "SwiftUI.MaterialBackdropProxy.(Storage in _DEF3755CDC6B87C0368876C9F497EC3D)", in: machOFile)
        #expect(storageFields["data"] == "Synchronization.Mutex<SwiftUI.MaterialBackdropProxy.(Storage in _DEF3755CDC6B87C0368876C9F497EC3D).Data>")
    }

    /// A witness built from a `some` result that lives in ANOTHER image —
    /// `SidebarListBody.CollectionViewBody.Body` is `ModifiedContent<opaque
    /// (View.staticIf), …>` and `View.staticIf` is SwiftUICore's — reaches
    /// that descriptor through a bind, a name; located through the same
    /// search paths the thunk reader infers from the file's location, it
    /// expands like any other. Measured before: 207 witnesses of this build
    /// printed `<<opaque return type of …>>`.
    @Test func aWitnessNamingAnotherImagesOpaqueTypeExpands() async throws {
        let machOFile = try loadSwiftUI()
        var collectionViewBodyWitness: String?
        var byNameLeftovers: [String] = []
        for associatedType in try machOFile.swift.associatedTypes {
            let conformingTypeName = await (try SymbolicDemangler.demangleType(for: associatedType.conformingTypeName, in: machOFile)).print(using: DemangleOptions.default)
            for record in associatedType.records {
                guard let mangledName = try? record.substitutedTypeName(in: machOFile),
                      let node = try? SymbolicDemangler.demangleType(for: mangledName, in: machOFile),
                      node.contains(Node.Kind.opaqueType)
                else { continue }
                let resolved = node.resolveOpaqueTypeCollectingConditionalCandidates(in: machOFile).node
                if resolved.contains(Node.Kind.opaqueReturnTypeOf) { byNameLeftovers.append(conformingTypeName) }
                if conformingTypeName.hasPrefix("SwiftUI.SidebarListBody.(CollectionViewBody in "), try record.name(in: machOFile) == "Body" {
                    collectionViewBodyWitness = await resolved.print(using: DemangleOptions.default)
                }
            }
        }
        #expect(collectionViewBodyWitness?.hasPrefix("SwiftUI.ModifiedContent<SwiftUI.StaticIf<SwiftUI._SemanticFeature<SwiftUI.Semantics_v7>, ") == true, "\(String(describing: collectionViewBodyWitness))")
        #expect(byNameLeftovers.isEmpty, "still by name:\n\(byNameLeftovers.joined(separator: "\n"))")
    }

    /// Every branch comment names what the cache names — the whole
    /// `ModifiedContent<…>` a thunk's shared tail wraps around the looked-up
    /// type, never the looked-up type alone — and nothing is left unread.
    @Test func theConditionalWitnessesReadAsTheCacheDoes() async throws {
        let machOFile = try loadSwiftUI()
        var dumpsWithBranches: [String] = []
        var unread: [String] = []
        for associatedType in try machOFile.swift.associatedTypes {
            var hasConditionalWitness = false
            for record in associatedType.records {
                guard let mangledName = try? record.substitutedTypeName(in: machOFile),
                      let node = try? SymbolicDemangler.demangleType(for: mangledName, in: machOFile),
                      node.contains(Node.Kind.opaqueType)
                else { continue }
                let resolution = node.resolveOpaqueTypeCollectingConditionalCandidates(in: machOFile)
                let text = await resolution.node.print(using: DemangleOptions.default)
                if text.contains("accessor function at") { unread.append(text) }
                if resolution.conditionalCandidates.count >= 2 { hasConditionalWitness = true }
            }
            guard hasConditionalWitness else { continue }
            dumpsWithBranches.append(try await associatedType.dump(using: .demangleOptions(.default), in: machOFile).string)
        }
        #expect(unread.isEmpty, "still unread:\n\(unread.joined(separator: "\n"))")

        let joined = dumpsWithBranches.joined(separator: "\n")
        #expect(joined.contains("//   iOS 26.4 or later: SwiftUI.ModifiedContent<SwiftUI._ViewModifier_Content<SwiftUI.OnModifierKeysChangedModifier>, SwiftUI._TaskModifier2>"), "\(joined)")
        #expect(joined.contains("//   before iOS 26.4:   SwiftUI.ModifiedContent<SwiftUI._ViewModifier_Content<SwiftUI.OnModifierKeysChangedModifier>, SwiftUI._TaskModifier>"), "\(joined)")
        // `FeedbackGenerator<A>.Body` reaches its thunk through a by-name
        // opaque reference (`<<opaque return type of View.onChange…>>`, an
        // anonymous-context descriptor), which the dump path does not expand
        // offline — a limitation older than this batch. What must not come
        // back is the fallback's reading of that thunk's generic accessor
        // without its arguments.
        #expect(!joined.contains("_TaskValueModifier2A"), "an unbound generic accessor was named without its arguments:\n\(joined)")
        #expect(joined.contains("SwiftUI._TagTraitWritingModifier<SwiftUI.ViewIdentity>"), "\(joined)")
    }
}

/// SwiftUI as an iOS 27 simulator runtime ships it: inside the runtime's
/// own `dyld_sim_shared_cache_arm64`, whose cross-image calls are rebases
/// like any cache's. Pinned so the cache reader's support for the simulator
/// format (magic `dyld_v1   arm64`, a `.01` subcache) is a test rather than
/// a one-off measurement.
@Suite(.serialized, .enabled(if: SimulatorRuntimeThunkFixtures.hasSimulatorCache))
struct SimulatorCacheSwiftUIThunkTests {
    @Test func everyAccessorReferenceResolvesInsideTheSimulatorCache() async throws {
        let cache = try DyldCache(path: .iOS_27_0_Simulator)
        let machO = try #require(cache.machOFile(named: .SwiftUI))
        var unread: [String] = []
        var conditionalWitnessCount = 0
        for associatedType in try machO.swift.associatedTypes {
            for record in associatedType.records {
                guard let mangledName = try? record.substitutedTypeName(in: machO),
                      let node = try? SymbolicDemangler.demangleType(for: mangledName, in: machO),
                      node.contains(Node.Kind.opaqueType)
                else { continue }
                let resolution = node.resolveOpaqueTypeCollectingConditionalCandidates(in: machO)
                let text = await resolution.node.print(using: DemangleOptions.default)
                if text.contains("accessor function at") { unread.append(text) }
                if resolution.conditionalCandidates.count >= 2 { conditionalWitnessCount += 1 }
            }
        }
        #expect(unread.isEmpty, "still unread:\n\(unread.joined(separator: "\n"))")
        #expect(conditionalWitnessCount > 0, "the iOS 27 simulator's SwiftUI is expected to carry availability-conditional witnesses")
    }
}

/// Where the archived-cache-gated suite below finds its cache. A separate
/// type on purpose: a `@Suite(.enabled(if:))` condition that reads a static
/// of the suite it decorates is a circular macro reference.
enum ArchivedMacOSCacheMergedAccessorFixtures {
    /// macOS 26.6, whose SwiftUICore still names the two fields below
    /// through accessor-function references. The suite used to read the
    /// running system's cache instead, and went red once that system moved
    /// on: macOS 27.0's SwiftUICore (and the 26.7 build it was first
    /// observed failing on) spells `Synchronization.Mutex<…>` directly in
    /// both mangled names, leaving nothing to read.
    static let cachePath = "/Volumes/DyldSharedCaches/macOS/26.6/dyld_shared_cache_arm64e"
    static var hasCache: Bool { FileManager.default.fileExists(atPath: cachePath) }
}

/// The same two SwiftUICore fields in a macOS dyld shared cache, where the
/// merged body's `x3` is a *rebased* pointer to libswiftSynchronization's
/// accessor rather than a bind: a register call through an address outside
/// this image has to reach the cache's image table, not this image's
/// indexes (whose offset conversion answers for the whole cache and so
/// cannot tell a foreign address apart). The private discriminators move
/// with the build, so only the type's own spelling is pinned.
@Suite(.serialized, .enabled(if: ArchivedMacOSCacheMergedAccessorFixtures.hasCache))
struct ArchivedMacOSCacheSwiftUICoreMergedAccessorTests {
    @Test func theMergedAccessorFieldsAreReadInTheCache() throws {
        let cache = try DyldCache(url: URL(fileURLWithPath: ArchivedMacOSCacheMergedAccessorFixtures.cachePath))
        let machOFile = try #require(cache.machOFile(named: .SwiftUICore), "the archived cache has no SwiftUICore")
        var texts: [String: String] = [:]
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let name = try? SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default),
                  name == "SwiftUI.PlatformAccessibilitySettingsDefinition" || name == "SwiftUI.NamedImage.Cache",
                  let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile)
            else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile),
                      typeNode.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                texts["\(name).\(try record.fieldName(in: machOFile))"] = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout).print(using: .default)
            }
        }
        try #require(texts.count == 2, "the premise: this cache's SwiftUICore names both fields through accessor-function references")
        #expect(texts["SwiftUI.PlatformAccessibilitySettingsDefinition.cache"]?.hasPrefix("Synchronization.Mutex<SwiftUI.PlatformAccessibilitySettingsDefinition.(Storage in ") == true, "\(texts)")
        #expect(texts["SwiftUI.NamedImage.Cache.data"]?.hasPrefix("Synchronization.Mutex<SwiftUI.NamedImage.Cache.(Data in ") == true, "\(texts)")
    }
}

