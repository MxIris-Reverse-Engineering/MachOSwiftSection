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
            let node = try SymbolicDemangler.demangleType(for: mangledTypeName, in: machOImage)
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
            let node = try SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile)
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
    /// non-generic multi-payload enum in the fixture must produce an enum
    /// layout through the runtime renderer when `printEnumLayout` is on —
    /// noncopyable ones included, whose payload field records carry kind-9
    /// (accessor-function) symbolic references; see the test below.
    @MainActor
    @Test func everyFixtureMultiPayloadEnumRendersALayout() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        var checkedEnumCount = 0
        for type in try machOImage.swift.types {
            guard case .enum(let enumType) = type, !enumType.descriptor.isGeneric, enumType.isMultiPayload else { continue }
            let renderer = FieldLayoutRenderer(type: type, metadata: nil, machO: machOImage, configuration: configuration)
            let enumLayout = await renderer.enumLayout
            #expect(enumLayout != nil, "no layout for \(enumType.descriptor)")
            checkedEnumCount += 1
        }
        try #require(checkedEnumCount > 0, "fixture must contain non-generic multi-payload enums")
    }

    /// `AccessorFunctionReferences.NoncopyablePayloadEnumTest` is
    /// `~Copyable`, so its payload field records name their types through
    /// kind-9 (accessor-function) symbolic references. The in-process backend
    /// asks the runtime for each payload type
    /// (`swift_getTypeByMangledNameInContext`, which runs the accessor), so
    /// the layout follows from the source like any other: both payloads are
    /// one `Int` wide and have no spare bits, so an extra tag byte after the
    /// 8-byte payload area tells the cases apart — `holding` 0, `boxed` 1, and
    /// the empty case 2 over a zeroed payload area.
    ///
    /// This test used to pin the opposite, that such an enum degrades to no
    /// layout, as a trip-wire for the day kind-9 payloads resolved; it had
    /// been failing on `next` since at least 2026-09-17.
    @MainActor
    @Test func noncopyableMultiPayloadEnumLaysOutFromItsResolvedPayloads() async throws {
        var configuration = DeclarationRenderConfiguration.demangleOptions(.default)
        configuration.printEnumLayout = true

        let noncopyableEnumType = try #require(try machOImage.swift.types.first { type in
            guard case .enum(let enumType) = type else { return false }
            return try enumType.descriptor.name(in: machOImage) == "NoncopyablePayloadEnumTest"
        }, "fixture must contain AccessorFunctionReferences.NoncopyablePayloadEnumTest")
        let renderer = FieldLayoutRenderer(type: noncopyableEnumType, metadata: nil, machO: machOImage, configuration: configuration)
        let enumLayout = try #require(await renderer.enumLayout)

        #expect(enumLayout.tagRegion?.range == 8 ..< 9)
        #expect(enumLayout.numTags == 3)
        #expect(enumLayout.cases.map(\.declaredName) == ["holding", "boxed", "empty"])
        #expect(enumLayout.cases.map(\.tagValue) == [0, 1, 2])
        #expect(enumLayout.cases.map(\.isPayloadCase) == [true, true, false])
    }
}
