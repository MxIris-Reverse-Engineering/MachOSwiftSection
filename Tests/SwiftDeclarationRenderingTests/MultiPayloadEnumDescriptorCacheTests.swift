import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftDeclarationRendering
import Demangling
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Pins the restored `MultiPayloadEnumDescriptorCache` (deleted by the leaf
/// migration's `ebb04d3`, which replaced it with a per-enum throwing linear
/// rescan of `__swift5_mpenum`).
///
/// The regression being guarded: with the rescan, a single undemanglable
/// descriptor anywhere in the section made `computeEnumLayout` throw, and the
/// `try?` above it suppressed the *whole* enum-layout comment block for every
/// multi-payload enum in the image. The cache restores the pre-refactor
/// contract — built once per image, published as a *partial* map (its build
/// loop catches instead of throwing), looked up without throwing — so a bad
/// descriptor can only make its own enum miss and fall back to the
/// tagged-projection layout.
@Suite(.serialized)
final class MultiPayloadEnumDescriptorCacheTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Every descriptor the fixture's `__swift5_mpenum` section carries must
    /// be reachable through the cache under its demangled type node — the
    /// build sweep must not silently drop entries.
    @MainActor
    @Test func cacheIndexesEveryFixtureDescriptor() async throws {
        let multiPayloadEnumDescriptors = try machOImage.swift.multiPayloadEnumDescriptors
        try #require(!multiPayloadEnumDescriptors.isEmpty, "fixture must carry multi-payload enum descriptors for this test to be meaningful")

        for multiPayloadEnumDescriptor in multiPayloadEnumDescriptors {
            let mangledTypeName = try multiPayloadEnumDescriptor.mangledTypeName(in: machOImage)
            let node = try MetadataReader.demangleType(for: mangledTypeName, in: machOImage)
            let cached = MultiPayloadEnumDescriptorCache.shared.multiPayloadEnumDescriptor(for: node, in: machOImage)
            #expect(cached != nil, "cache missed a descriptor the build sweep should have indexed")
        }
    }

    /// The per-descriptor error contract, stated by this type's own doc
    /// comment: one unreadable descriptor degrades **only its own enum**.
    ///
    /// Splices a deliberately unreadable descriptor (a real layout re-wrapped
    /// far past the fixture's end of file, so every relative resolve throws)
    /// into the middle of the real descriptor list. With a loop-level `catch`
    /// the throw exits the whole loop, so every descriptor AFTER the bad one is
    /// missing from the published map and its enum silently falls back to the
    /// tagged projection — a wrong layout, not a missing one, memoized for the
    /// image's lifetime because the map is a `SharedCache` entry.
    @MainActor
    @Test func oneUnreadableDescriptorDoesNotDropTheOnesAfterIt() throws {
        let realDescriptors = try machOFile.swift.multiPayloadEnumDescriptors
        try #require(realDescriptors.count >= 2, "fixture must carry at least two multi-payload enum descriptors for this test to be meaningful")

        let unreadableDescriptor = MultiPayloadEnumDescriptor(layout: realDescriptors[0].layout, offset: 0x0FFF_FFF0)
        let splicedDescriptors = [unreadableDescriptor] + realDescriptors

        let indexedDescriptorByNode = MultiPayloadEnumDescriptorCache.indexDescriptors(splicedDescriptors, in: machOFile)

        for realDescriptor in realDescriptors {
            let mangledTypeName = try realDescriptor.mangledTypeName(in: machOFile)
            let node = try MetadataReader.demangleType(for: mangledTypeName, in: machOFile)
            #expect(
                indexedDescriptorByNode[node] != nil,
                "a descriptor after the unreadable one was dropped — the catch is truncating the map instead of skipping one entry"
            )
        }
    }

    /// A lookup miss is a plain `nil`, never an error — the caller's
    /// tagged-projection fallback depends on that (the pre-refactor
    /// degradation contract for enums whose descriptor could not be indexed).
    @MainActor
    @Test func unknownNodeMissesWithoutThrowing() {
        let moduleNode = Node.create(kind: .module, contents: .text("Swift"))
        let identifierNode = Node.create(kind: .identifier, contents: .text("DefinitelyNotAMultiPayloadEnum"))
        let enumNode = Node.create(kind: .enum, children: [moduleNode, identifierNode])
        let typeNode = Node.create(kind: .type, children: [enumNode])

        let cached = MultiPayloadEnumDescriptorCache.shared.multiPayloadEnumDescriptor(for: typeNode, in: machOImage)
        #expect(cached == nil)
    }

    /// Presence trip-wire for the wholesale-suppression regression: every
    /// non-generic **copyable** multi-payload enum in the fixture must produce
    /// an enum layout through the runtime renderer when `printEnumLayout` is
    /// on. Noncopyable enums are excluded: their payload field records carry
    /// kind-9 (accessor-function) symbolic references, which the static
    /// demangle path cannot resolve to a payload size — they degrade to no
    /// layout by design (pinned separately below; resolving them in-process
    /// is the recorded layer-1 follow-up in
    /// `Documentations/Internal/AccessorFunctionReferenceRendering.md`).
    @MainActor
    @Test func everyFixtureMultiPayloadEnumRendersALayout() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        var checkedEnumCount = 0
        for type in try machOImage.swift.types {
            guard case .enum(let enumType) = type, !enumType.descriptor.isGeneric, enumType.isMultiPayload,
                  !(enumType.invertibleProtocolSet?.hasInvertedProtocols ?? false) else { continue }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
            let enumLayout = await renderer.enumLayout
            #expect(enumLayout != nil, "no layout for \(enumType.descriptor)")
            checkedEnumCount += 1
        }
        try #require(checkedEnumCount > 0, "fixture must contain non-generic multi-payload enums")
    }

    /// The honest-degradation contract for the excluded class above: a
    /// noncopyable multi-payload enum (kind-9 payload references) yields *no*
    /// layout rather than a fabricated one. If in-process resolution of
    /// accessor-function references lands (layer 1), this pin flips and must
    /// be updated deliberately together with the sweep's exclusion.
    @MainActor
    @Test func noncopyableMultiPayloadEnumDegradesToNoLayout() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        var checkedEnumCount = 0
        for type in try machOImage.swift.types {
            guard case .enum(let enumType) = type, !enumType.descriptor.isGeneric, enumType.isMultiPayload,
                  enumType.invertibleProtocolSet?.hasInvertedProtocols == true else { continue }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
            let enumLayout = await renderer.enumLayout
            #expect(enumLayout == nil, "unexpected layout for noncopyable multi-payload enum \(enumType.descriptor) — layer 1 landed? update the sweep exclusion too")
            checkedEnumCount += 1
        }
        try #require(checkedEnumCount > 0, "fixture must contain a noncopyable multi-payload enum (AccessorFunctionReferences.NoncopyablePayloadEnumTest)")
    }
}
