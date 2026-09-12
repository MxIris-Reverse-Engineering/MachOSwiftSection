#if THUNK_ANALYSIS

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

/// The offline reading of a type-construction thunk against the runtime's
/// own answer.
///
/// For every kind-9 witness of a non-generic conformer in SwiftUI, the
/// offline resolution (the satisfied branch, what today's OS takes) must
/// print exactly what the runtime — which executes the thunk — returns for
/// the same witness. Both sides move together with the OS, so the assertion
/// stays green across upgrades while still failing the moment the evaluator
/// reads a branch wrong; and a wrong reading here is a *real, fully
/// qualified, wrong type*, which no eyeballing of the output would catch.
// The resolver is scoped to each test's task (`AccessorThunkResolution.taskResolver`),
// never installed process-wide: suites run in parallel, and a process-wide
// install turned every snapshot suite's kind-9 placeholders into real types
// for as long as it lasted.
@Suite(.serialized)
struct ConstructedThunkOracleTests {
    /// The two sides spell a private type's context differently and both
    /// spellings name the same type: the descriptor carries the private
    /// discriminator (`(Foo in _302179F1…).Static`), while the runtime's
    /// `_mangledTypeName` sees only an anonymous context
    /// (`(unknown context at $1bbe57830).Foo.Static`). Reduce both to the
    /// bare identifier so the comparison is about the type, not the
    /// spelling.
    private static func normalizingPrivateContexts(_ text: String) -> String {
        var normalized = text
        normalized = normalized.replacingOccurrences(of: #"\((\w+) in _[0-9A-F]+\)"#, with: "$1", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\(unknown context at \$[0-9a-fA-F]+\)\."#, with: "", options: .regularExpression)
        return normalized
    }

    @Test func offlineMatchesTheRuntimeForEveryNonGenericConformer() async throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .SwiftUI))
        guard dlopen("/System/Library/Frameworks/SwiftUI.framework/Versions/A/SwiftUI", RTLD_LAZY) != nil,
              let machOImage = MachOImage(name: "SwiftUI")
        else { return }

        // The image and the file describe the same binary, so the records
        // pair up by position.
        let fileAssociatedTypes = try machOFile.swift.associatedTypes
        let imageAssociatedTypes = try machOImage.swift.associatedTypes
        #expect(fileAssociatedTypes.count == imageAssociatedTypes.count)

        var compared = 0
        var mismatches: [String] = []
        for (fileAssociatedType, imageAssociatedType) in zip(fileAssociatedTypes, imageAssociatedTypes) {
            for (fileRecord, imageRecord) in zip(fileAssociatedType.records, imageAssociatedType.records) {
                let fileMangledName = try fileRecord.substitutedTypeName(in: machOFile)
                guard let fileNode = try? SymbolicDemangler.demangleType(for: fileMangledName, in: machOFile),
                      fileNode.contains(Node.Kind.opaqueType)
                else { continue }
                let imageMangledName = try imageRecord.substitutedTypeName(in: machOImage)
                guard let imageNode = try? SymbolicDemangler.demangleType(for: imageMangledName, in: machOImage),
                      let offlineUnresolved = try? imageNode.resolveOpaqueType(in: machOImage),
                      offlineUnresolved.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                // The runtime's answer exists only for a conformer it can
                // instantiate without arguments.
                guard let runtimeNode = InProcessAccessorFunctionResolution.witnessNode(
                    witnessMangledName: imageMangledName,
                    conformingTypeName: imageAssociatedType.conformingTypeName,
                    in: machOImage
                ) else { continue }

                let offlineNode = try AccessorThunkResolution.$taskResolver.withValue(DisassemblingAccessorThunkResolver()) {
                    try fileNode.resolveOpaqueType(in: machOFile)
                }
                let offlineText = Self.normalizingPrivateContexts(await offlineNode.print(using: DemangleOptions.default))
                let runtimeText = Self.normalizingPrivateContexts(await runtimeNode.print(using: DemangleOptions.default))
                compared += 1
                if offlineText != runtimeText {
                    mismatches.append("offline: \(offlineText)\nruntime: \(runtimeText)")
                }
            }
        }
        print("witnesses compared against the runtime: \(compared)")
        #expect(compared >= 3, "SwiftUI is expected to carry several kind-9 witnesses on non-generic conformers")
        #expect(mismatches.isEmpty, "the offline reading disagrees with the runtime:\n\(mismatches.joined(separator: "\n\n"))")
    }
}

#endif
