import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDeclarationRendering
import Demangling
@_spi(Internals) import SwiftInspection
import MachOFixtureSupport

/// The in-process leg of kind-9 resolution (evolution proposal
/// `offline-opaque-accessor-thunk-resolution`): a witness whose underlying
/// type is an accessor thunk is answered by the runtime running that thunk,
/// exactly as it would for the program itself.
///
/// Driven against SwiftUI loaded into the test process — the only binary at
/// hand that carries availability-conditional opaque types — and asserting
/// SHAPE, not type names, which drift with every OS release: an answered
/// witness carries no kind-9 reference and no erased opaque type, a generic
/// conformer is left exactly as the offline rewrite produced it.
@Suite(.serialized)
struct InProcessAccessorFunctionResolutionTests {
    private struct Outcome {
        var answered: [String] = []
        var unchanged: [String] = []
    }

    private func loadedSwiftUI() throws -> MachOImage? {
        guard dlopen("/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI", RTLD_LAZY) != nil else { return nil }
        return MachOImage(name: "SwiftUI")
    }

    private func resolveEveryAccessorWitness(in image: MachOImage) async throws -> Outcome {
        var outcome = Outcome()
        for associatedType in try image.swift.associatedTypes {
            for record in associatedType.records {
                let witnessMangledName = try record.substitutedTypeName(in: image)
                guard let node = try? SymbolicDemangler.demangleType(for: witnessMangledName, in: image),
                      node.contains(Node.Kind.opaqueType),
                      let offlineResolved = try? node.resolveOpaqueType(in: image),
                      offlineResolved.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                let resolved = try node.resolveOpaqueType(
                    witnessMangledName: witnessMangledName,
                    conformingTypeName: associatedType.conformingTypeName,
                    in: image
                )
                let text = await resolved.print(using: DemangleOptions.default)
                if resolved.contains(Node.Kind.accessorFunctionReference) {
                    outcome.unchanged.append(text)
                } else {
                    outcome.answered.append(text)
                }
            }
        }
        return outcome
    }

    @Test func theRuntimeAnswersAValueTypeConformersWitness() async throws {
        guard let image = try loadedSwiftUI() else { return }
        let outcome = try await resolveEveryAccessorWitness(in: image)

        print("kind-9 witnesses answered in-process: \(outcome.answered.count), left to the offline reader: \(outcome.unchanged.count)")
        for text in outcome.answered { print("  runtime: \(text.prefix(160))") }

        #expect(!outcome.answered.isEmpty, "SwiftUI is expected to carry a kind-9 witness on a non-generic value type the runtime can instantiate")
        #expect(outcome.answered.allSatisfy { !$0.contains("symbolic reference") && !$0.contains("accessor function at") })
        #expect(outcome.answered.allSatisfy { $0.hasPrefix("SwiftUI.") }, "the runtime's answer demangles to a fully qualified type")
    }

    /// A generic conformer has no metadata without arguments, so the runtime
    /// cannot answer and the tree comes back as the offline rewrite left it —
    /// the reference inside its type, never an erased opaque type.
    @Test func aGenericConformersWitnessIsLeftAsTheOfflineRewriteMadeIt() async throws {
        guard let image = try loadedSwiftUI() else { return }
        let outcome = try await resolveEveryAccessorWitness(in: image)

        #expect(!outcome.unchanged.isEmpty, "SwiftUI is expected to carry kind-9 witnesses on generic conformers (Slider, Toggle, …)")
        #expect(outcome.unchanged.allSatisfy { !$0.hasPrefix("opaque type ") })
    }

    /// The candidate-collecting entry takes the same in-process leg and
    /// reports no candidates: the runtime answers for this OS alone.
    @Test func theCandidateCollectingEntryTakesTheSameLegWithNoCandidates() async throws {
        guard let image = try loadedSwiftUI() else { return }
        var comparedWitnesses = 0
        for associatedType in try image.swift.associatedTypes {
            for record in associatedType.records {
                let witnessMangledName = try record.substitutedTypeName(in: image)
                guard let node = try? SymbolicDemangler.demangleType(for: witnessMangledName, in: image),
                      node.contains(Node.Kind.opaqueType),
                      let offlineResolved = try? node.resolveOpaqueType(in: image),
                      offlineResolved.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                let single = try node.resolveOpaqueType(witnessMangledName: witnessMangledName, conformingTypeName: associatedType.conformingTypeName, in: image)
                let collecting = node.resolveOpaqueTypeCollectingConditionalCandidates(witnessMangledName: witnessMangledName, conformingTypeName: associatedType.conformingTypeName, in: image)
                let singleText = await single.print(using: DemangleOptions.default)
                let collectingText = await collecting.node.print(using: DemangleOptions.default)
                #expect(singleText == collectingText)
                #expect(collecting.conditionalCandidates.isEmpty)
                comparedWitnesses += 1
            }
        }
        #expect(comparedWitnesses > 0)
    }
}
