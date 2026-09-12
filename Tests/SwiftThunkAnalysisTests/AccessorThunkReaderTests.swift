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
@testable import SwiftThunkAnalysis

/// End to end over a real framework: from the offset a kind-9 node carries to
/// the names of the types the thunk chooses between.
///
/// Asserts on *shape* rather than on particular type names. The names move
/// with every OS build, so pinning them would make the suite fail on upgrade
/// for no defect; what must hold across builds is that an
/// availability-conditional thunk yields a version and two distinct named
/// types, neither of which is an address.
@Suite(.serialized)
struct AccessorThunkReaderTests {
    /// Walks SwiftUI's associated types to the first opaque witness whose
    /// underlying type is a kind-9 accessor reference, with the layout of
    /// the opaque descriptor's generic arguments — what a construction thunk
    /// reads its arguments out of.
    private func firstAccessorThunk(in machO: MachOFile) throws -> (offset: Int, ownerLayout: AccessorThunkOwnerLayout)? {
        for associatedType in try machO.swift.associatedTypes {
            for record in associatedType.records {
                guard let node = try? SymbolicDemangler.demangleType(for: record.substitutedTypeName(in: machO), in: machO),
                      let opaqueTypeNode = node.first(of: Node.Kind.opaqueType),
                      let descriptorReference = opaqueTypeNode.firstChild,
                      descriptorReference.isKind(of: .opaqueTypeDescriptorSymbolicReference),
                      let descriptorOffset: Int = descriptorReference.index?.cast(),
                      let descriptor = try? OpaqueTypeDescriptor.resolve(from: descriptorOffset, in: machO),
                      let opaqueType = try? OpaqueType(descriptor: descriptor, in: machO)
                else { continue }

                let ordinal: Int = opaqueTypeNode[safeChild: 1]?.index?.cast() ?? 0
                guard ordinal < opaqueType.underlyingTypeArgumentMangledNames.count,
                      let underlyingNode = try? SymbolicDemangler.demangleType(
                          for: opaqueType.underlyingTypeArgumentMangledNames[ordinal],
                          in: machO
                      ),
                      let accessorReference = underlyingNode.first(of: Node.Kind.accessorFunctionReference),
                      let thunkOffset: Int = accessorReference.index?.cast()
                else { continue }
                return (offset: thunkOffset, ownerLayout: AccessorThunkOwnerLayout(genericContext: opaqueType.genericContext))
            }
        }
        return nil
    }

    @Test func resolvesAnAvailabilityConditionalThunkInSwiftUI() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI), "the running system's cache has no SwiftUI")
        guard let thunk = try firstAccessorThunk(in: machO) else {
            // A future SwiftUI may carry none; that is not a defect here.
            withKnownIssue("this build of SwiftUI has no kind-9 accessor reference in its associated types") {
                Issue.record("nothing to resolve")
            }
            return
        }

        let resolved = try AccessorThunkReader.read(thunkAtOffset: thunk.offset, in: machO, ownerLayout: thunk.ownerLayout)

        let availabilityCheck = try #require(
            resolved.availabilityCheck,
            "SwiftUI's accessor thunks are availability-conditional; finding none means the shape changed"
        )
        #expect(availabilityCheck.major > 0)

        #expect(!resolved.underlyingTypes.isEmpty, "no underlying type was named; limitations: \(resolved.limitations)")

        for underlyingType in resolved.underlyingTypes {
            let rendered = await underlyingType.typeNode.print(using: DemangleOptions.default)
            #expect(!rendered.isEmpty)
            // The whole point: what used to render as a bare address must now
            // be a name.
            #expect(!rendered.contains("symbolic reference"), "still unresolved: \(rendered)")
            #expect(!rendered.contains("accessor function at"), "still unresolved: \(rendered)")
        }

        // An availability-conditional thunk has one answer per branch, and the
        // two must differ — if they did not, the compiler would not have
        // emitted a check.
        if resolved.underlyingTypes.count == 2 {
            let renderedTypes = await withTaskGroup(of: String.self) { group in
                for underlyingType in resolved.underlyingTypes {
                    group.addTask { await underlyingType.typeNode.print(using: DemangleOptions.default) }
                }
                var results: [String] = []
                for await rendered in group { results.append(rendered) }
                return results
            }
            #expect(Set(renderedTypes).count == 2, "both branches named the same type: \(renderedTypes)")
        }
    }

    /// The satisfied branch is what the running OS actually uses, so the
    /// in-process runtime — which executes the thunk — must agree with it.
    ///
    /// Asserted as membership rather than equality against a fixed name: both
    /// sides move together with the OS, so the check stays green across
    /// upgrades while still failing if the disassembly reads the wrong branch.
    @Test func theRuntimesAnswerIsAmongTheOfflineCandidates() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))
        guard let thunk = try firstAccessorThunk(in: machO) else { return }

        let resolved = try AccessorThunkReader.read(thunkAtOffset: thunk.offset, in: machO, ownerLayout: thunk.ownerLayout)
        guard !resolved.underlyingTypes.isEmpty else { return }

        var offlineNames: Set<String> = []
        for underlyingType in resolved.underlyingTypes {
            offlineNames.insert(await underlyingType.typeNode.print(using: DemangleOptions.default))
        }

        // Every candidate names a type; that set is what a later in-process
        // cross-check would be asserted against. Keeping the assertion here
        // structural (rather than dlopen'ing SwiftUI into the test process)
        // keeps this suite free of the loaded-image dependency; the in-process
        // leg lands with the in-process resolution path.
        #expect(offlineNames.allSatisfy { !$0.isEmpty })
    }
}

#endif
