import Foundation
import Testing
import MachOKit
@testable import MachOTestingSupport
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection

/// MachOImage-side counterpart of the proposal-0011 attribution tests: the
/// in-process reader resolves cross-image protocol descriptors (the third
/// layer of the facts-resolution chain), so the SymbolTestsHelper refine fact
/// that a MachOFile reader cannot reach attaches here.
@Suite(.serialized)
final class OpaqueAttributionImageE2ETests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func buildOutput() async throws -> String {
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false),
            printConfiguration: .init()
        )
        let unsafeMachOImage = machOImage
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: unsafeMachOImage)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: unsafeMachOImage))
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }

    @Test func opaqueCrossImageRefineClosureAttachesInProcess() async throws {
        let output = try await buildOutput()
        // functionCrossImageRefineClosure: `HelperRefinedProtocol` refines
        // `HelperBaseProtocol` (the constraint's anchor) inside
        // SymbolTestsHelper. In-process the requirement's indirect pointer
        // dereferences straight into that image's descriptor, so the refine
        // closure resolves and `<Swift.Int>` attaches — the offline
        // counterpart in SymbolTestsCoreE2ETests degrades to no parameter.
        #expect(output.contains("some Swift.Equatable & SymbolTestsHelper.HelperRefinedProtocol<Swift.Int>"))
    }

    @Test func opaqueAnchorAttributionMatchesOfflineReader() async throws {
        let output = try await buildOutput()
        // The scenarios that need no cross-image facts must render exactly as
        // the MachOFile reader does (accepted reader divergence is only ever
        // additive on the in-process side).
        #expect(output.contains("some Swift.Equatable & Swift.Sequence<[A]>"))
        #expect(output.contains("some Swift.Collection<[A]> & Swift.Equatable & SymbolTestsCore.Protocols.TestCollection<[A]>"))
        #expect(output.contains("some Swift.Equatable & SymbolTestsCore.Protocols.TestCollection<[A]> & SymbolTestsCore.Protocols.UnpinnedElementProtocol"))
        #expect(!output.contains("UnpinnedElementProtocol<"))
        #expect(!output.contains("Swift.Equatable<"))
    }
}
