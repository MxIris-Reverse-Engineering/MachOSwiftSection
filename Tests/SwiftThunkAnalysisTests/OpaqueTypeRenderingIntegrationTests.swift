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

/// The point of the whole module: an associated-type witness that rendered as
/// a bare address renders as a type once the thunk is read — and, since the
/// follow-up batch, as its type *around* the unread reference when it cannot
/// be. The disassembling resolver is the default for every task; the
/// "cannot be read" side is pinned by scoping a resolver that answers nothing.
@Suite(.serialized)
struct OpaqueTypeRenderingIntegrationTests {
    private static let unreadReferenceMarker = "accessor function at"
    private static let erasedTypeMarker = "symbolic reference"

    /// Renders every SwiftUI associated-type witness that carries an opaque
    /// type, keeping the ones a kind-9 accessor reference is involved in:
    /// still unread (`accessor function at N`), erased the way they used to
    /// be (`opaque type symbolic reference 0x…`), or resolved to one of the
    /// types the thunks are known to name.
    private func renderedWitnesses(in machO: MachOFile) async throws -> [String] {
        var rendered: [String] = []
        for associatedType in try machO.swift.associatedTypes {
            for record in associatedType.records {
                guard let node = try? SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machO), in: machO),
                      node.contains(Node.Kind.opaqueType),
                      let resolved = try? node.resolveOpaqueType(in: machO)
                else { continue }
                let text = await resolved.print(using: DemangleOptions.default)
                guard text.contains(Self.unreadReferenceMarker)
                    || text.contains(Self.erasedTypeMarker)
                    || text.contains("SwiftUI.(AllowsWindowActivationEventsModifier")
                    || text.contains("TaskModifier")
                else { continue }
                rendered.append(text)
            }
        }
        return rendered
    }

    @Test func readingTheThunksNamesTypesThatWereBareAddresses() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        let before = try await AccessorThunkResolution.$taskResolver.withValue(UnreadableAccessorThunkResolver()) {
            try await renderedWitnesses(in: machO)
        }
        let unreadBefore = before.filter { $0.contains(Self.unreadReferenceMarker) }.count

        let after = try await renderedWitnesses(in: machO)
        let unreadAfter = after.filter { $0.contains(Self.unreadReferenceMarker) }.count

        print("unread accessor references before: \(unreadBefore), after: \(unreadAfter)")
        for text in after where !text.contains(Self.unreadReferenceMarker) {
            print("  now renders: \(text)")
        }

        #expect(
            unreadAfter < unreadBefore,
            "reading the thunks did not reduce the number of unread accessor references (\(unreadBefore) → \(unreadAfter))"
        )
    }

    /// The goal the module exists for: no kind-9 witness in SwiftUI is left
    /// unread — the type-construction evaluator reads the thunk the first
    /// landing had to refuse.
    @Test func everyAccessorReferenceResolves() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        let rendered = try await renderedWitnesses(in: machO)
        let unread = rendered.filter { $0.contains(Self.unreadReferenceMarker) }
        #expect(unread.isEmpty, "still unread:\n\(unread.joined(separator: "\n"))")
    }

    /// When the reader cannot read the thunk the reference is not resolved —
    /// but it is no longer erased either. Before the follow-up batch the rewriter gave
    /// up on any underlying type that was not a `.type` node, and the whole
    /// witness printed as `opaque type symbolic reference 0x…` with its
    /// generic arguments thrown away. Now the reference prints as
    /// `accessor function at N` inside the type it sits in.
    @Test func whenTheThunkCannotBeReadTheReferenceStaysInsideItsType() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        let rendered = try await AccessorThunkResolution.$taskResolver.withValue(UnreadableAccessorThunkResolver()) {
            try await renderedWitnesses(in: machO)
        }
        let unread = rendered.filter { $0.contains(Self.unreadReferenceMarker) }

        #expect(!unread.isEmpty, "SwiftUI is expected to carry kind-9 witnesses that this resolver leaves unread")
        #expect(
            unread.allSatisfy { !$0.hasPrefix("opaque type ") },
            "an unread reference must print inside its type, not erase it"
        )
        #expect(
            unread.contains { $0.contains("<") },
            "at least one unread reference sits inside a generic type whose arguments used to be thrown away"
        )
    }

    /// The other branch is not lost: asked for candidates, the resolution
    /// reports every branch, each rendered in place of the whole witness.
    @Test func theOtherBranchIsReportedAsACandidate() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        var twoWayResolutions: [Node.OpaqueTypeResolution] = []
        do {
            for associatedType in (try? machO.swift.associatedTypes) ?? [] {
                for record in associatedType.records {
                    guard let node = try? SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machO), in: machO),
                          node.contains(Node.Kind.opaqueType)
                    else { continue }
                    let resolution = node.resolveOpaqueTypeCollectingConditionalCandidates(in: machO)
                    guard resolution.conditionalCandidates.count >= 2 else { continue }
                    twoWayResolutions.append(resolution)
                }
            }
        }
        let resolution = try #require(twoWayResolutions.first, "SwiftUI is expected to carry an availability-conditional witness the reader resolves both ways")

        var candidateTexts: [String] = []
        for candidate in resolution.conditionalCandidates {
            candidateTexts.append(await candidate.substitutedNode.print(using: DemangleOptions.default))
        }
        let currentText = await resolution.node.print(using: DemangleOptions.default)
        print("current: \(currentText)")
        for (candidate, text) in zip(resolution.conditionalCandidates, candidateTexts) {
            print("  \(candidate.availability.map { "\($0.isSatisfiedBranch ? "≥" : "<") \($0.major).\($0.minor)" } ?? "unconditional"): \(text)")
        }

        #expect(candidateTexts.first == currentText, "the first candidate is the branch the single-value rendering takes")
        #expect(Set(candidateTexts).count == candidateTexts.count, "each branch renders a different witness")
        #expect(resolution.conditionalCandidates.allSatisfy { $0.availability != nil }, "an availability-conditional thunk gates every branch")
        #expect(resolution.conditionalCandidates.filter { $0.availability?.isSatisfiedBranch == true }.count == 1)
        #expect(candidateTexts.allSatisfy { !$0.contains(Self.unreadReferenceMarker) && !$0.contains(Self.erasedTypeMarker) })
    }
}
