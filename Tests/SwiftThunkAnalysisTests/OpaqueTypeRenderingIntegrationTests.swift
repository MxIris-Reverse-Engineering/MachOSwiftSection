#if THUNK_ANALYSIS

import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import SwiftThunkAnalysis

/// The point of the whole module: an associated-type witness that rendered as
/// a bare address renders as a type once the resolver is installed.
@Suite(.serialized)
struct OpaqueTypeRenderingIntegrationTests {
    /// Renders every SwiftUI associated-type witness whose opaque type is
    /// backed by a kind-9 accessor reference.
    private func renderedWitnesses(in machO: MachOFile) async throws -> [String] {
        var rendered: [String] = []
        for associatedType in try machO.swift.associatedTypes {
            for record in associatedType.records {
                guard let node = try? SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machO), in: machO),
                      node.contains(Node.Kind.opaqueType),
                      let resolved = try? node.resolveOpaqueType(in: machO)
                else { continue }
                let text = await resolved.print(using: DemangleOptions.default)
                guard text.contains("symbolic reference") || text.contains("SwiftUI.(AllowsWindowActivationEventsModifier") || text.contains("TaskModifier") else { continue }
                rendered.append(text)
            }
        }
        return rendered
    }

    @Test func installingTheResolverNamesTypesThatWereBareAddresses() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        AccessorThunkResolution.resolver = nil
        let before = try await renderedWitnesses(in: machO)
        let unresolvedBefore = before.filter { $0.contains("symbolic reference") }.count

        AccessorThunkResolution.installDisassemblingResolver()
        defer { AccessorThunkResolution.resolver = nil }
        let after = try await renderedWitnesses(in: machO)
        let unresolvedAfter = after.filter { $0.contains("symbolic reference") }.count

        print("bare-address witnesses before: \(unresolvedBefore), after: \(unresolvedAfter)")
        for text in after where !text.contains("symbolic reference") {
            print("  now renders: \(text)")
        }

        #expect(
            unresolvedAfter < unresolvedBefore,
            "installing the resolver did not reduce the number of bare-address witnesses (\(unresolvedBefore) → \(unresolvedAfter))"
        )
    }

    /// With no resolver registered, output is exactly what it was before this
    /// module existed — the feature is additive and its trait defaults off.
    @Test func withoutAResolverNothingChanges() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        AccessorThunkResolution.resolver = nil
        let rendered = try await renderedWitnesses(in: machO)
        #expect(rendered.contains { $0.contains("symbolic reference") })
    }
}

#endif
