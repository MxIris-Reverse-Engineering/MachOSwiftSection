import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import Demangling
@_spi(Internals) import SwiftInspection
@testable import SwiftThunkAnalysis

/// Runs the reader over every kind-9 accessor reference in a real framework
/// and prints what each one resolved to.
///
/// **A survey, not an assertion.** Kept because the resolution *rate* is the
/// number that decides whether a new thunk shape is worth teaching the
/// analyzer, and it can only be measured against a real framework. Measured on
/// SwiftUI (macOS 26 shared cache, 2026-09-11): 14 records over 3 distinct
/// thunks, of which 2 resolve completely (both branches named) and 1 resolves
/// neither branch — one branch builds its type through a chain of calls, the
/// other calls something that is not a plain metadata accessor.
@Suite(.disabled("Survey probe — enable explicitly to measure the resolution rate"))
struct ThunkResolutionSurveyProbe {
    @Test func printsResolutionOfEveryThunk() async throws {
        let cache = try DyldCache(path: .current)
        let machO = try #require(cache.machOFile(named: .SwiftUI))

        var seenThunkOffsets: Set<Int> = []
        var recordCount = 0

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
                      let underlyingNode = try? SymbolicDemangler.demangleType(for: opaqueType.underlyingTypeArgumentMangledNames[ordinal], in: machO),
                      let accessorReference = underlyingNode.first(of: Node.Kind.accessorFunctionReference),
                      let thunkOffset: Int = accessorReference.index?.cast()
                else { continue }

                recordCount += 1
                guard seenThunkOffsets.insert(thunkOffset).inserted else { continue }

                let conformingTypeName = await (try SymbolicDemangler.demangleType(for: associatedType.conformingTypeName, in: machO))
                    .print(using: DemangleOptions.default)
                let resolved = try AccessorThunkReader.read(thunkAtOffset: thunkOffset, in: machO)
                print("######## \(conformingTypeName).\(try record.name(in: machO))")
                if let check = resolved.availabilityCheck {
                    print("  if #available(platform \(check.platform), \(check.major).\(check.minor).\(check.patch))")
                }
                for underlyingType in resolved.underlyingTypes {
                    let rendered = await underlyingType.typeNode.print(using: DemangleOptions.default)
                    print("  \(underlyingType.condition): \(rendered)")
                }
                for limitation in resolved.limitations {
                    print("  unread: \(limitation)")
                }
            }
        }
        print("records with a kind-9 underlying type: \(recordCount), distinct thunks: \(seenThunkOffsets.count)")
    }

}
