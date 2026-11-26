#if os(macOS)

import Foundation
import Testing
import MachOKit
import MachOKitExtensions
import CrossReferenceAnalysis
import SwiftSectionKit
import SwiftSectionFixtureSupport

/// `refs --type`: the references to a Swift type, by its mangling or by a
/// symbol of it (evolution proposal `cross-reference-recall-gaps`).
@Suite
struct ReferencesRequestSwiftTypeTests {
    private static func isTypeReference(_ target: CodeReferenceTarget) -> Bool {
        switch target {
        case .swiftType, .swiftTypeName, .objectiveCClass: true
        default: false
        }
    }

    /// SwiftUICore's `Text`, whichever of its manglings or symbols names it.
    @Test(.enabled(if: FullDyldCache.cachedHost != nil, "needs the running system's dyld shared cache"))
    func typeSubjectFindsTheSameReferencesWhateverNamesTheType() async throws {
        let byMangling = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .swiftType("7SwiftUI4TextV", imageName: nil), imageNames: ["SwiftUICore"]).run(output: RecordingOutput())
        #expect(!byMangling.rows.isEmpty)
        #expect(byMangling.rows.allSatisfy { Self.isTypeReference($0.reference.target) })
        // Calls to the metadata accessor, and its address taken.
        #expect(byMangling.rows.contains { $0.reference.kind == .call })
        for spelling in ["$s7SwiftUI4TextVMn", "_$s7SwiftUI4TextVMa", "$s7SwiftUI4TextVN"] {
            let bySymbol = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .swiftType(spelling, imageName: nil), imageNames: ["SwiftUICore"]).run(output: RecordingOutput())
            #expect(bySymbol.rows == byMangling.rows, "\(spelling)")
        }
    }

    @Test(.enabled(if: FullDyldCache.cachedHost != nil, "needs the running system's dyld shared cache"))
    func typeSubjectInACacheNeedsTheImageOfATypeNoImageExports() async throws {
        await #expect(throws: CrossReferenceRequestError.swiftTypeNeedsImage(mangling: "11NoSuchTypes7NothingV")) {
            try await ReferencesRequest(input: .systemDyldSharedCache, subject: .swiftType("$s11NoSuchTypes7NothingVMn", imageName: nil)).run(output: RecordingOutput())
        }
        await #expect(throws: CrossReferenceRequestError.swiftTypeNotFound(mangling: "11NoSuchTypes7NothingV")) {
            try await ReferencesRequest(input: .systemDyldSharedCache, subject: .swiftType("11NoSuchTypes7NothingV", imageName: "SwiftUICore")).run(output: RecordingOutput())
        }
    }

    /// A type no symbol names — its descriptor symbol stripped — is looked
    /// for in every file of a set of files, which are few.
    @Test func typeSubjectLooksForAnUnexportedTypeInEveryStandaloneFile() async throws {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "HiddenTypeReferences",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "HiddenTypeReferences.swift", contents: """
            struct Hidden {
                var value: Int
            }

            public func makeHidden() -> Any {
                Hidden(value: 1)
            }
            """)],
            arguments: ["-swift-version", "5", "-Xlinker", "-x"]
        )
        let input = CrossReferenceInput.files(paths: [libraryURL.path], architecture: nil)
        let byMangling = try await ReferencesRequest(input: input, subject: .swiftType("20HiddenTypeReferences6HiddenV", imageName: nil)).run(output: RecordingOutput())
        #expect(!byMangling.rows.isEmpty)
        #expect(byMangling.rows.allSatisfy { Self.isTypeReference($0.reference.target) })
        // A symbol of the type names it too, its prefix and suffix taken off.
        for spelling in ["$s20HiddenTypeReferences6HiddenVMn", "_$s20HiddenTypeReferences6HiddenVMa", "$s20HiddenTypeReferences6HiddenVN"] {
            let bySymbol = try await ReferencesRequest(input: input, subject: .swiftType(spelling, imageName: nil)).run(output: RecordingOutput())
            #expect(bySymbol.rows == byMangling.rows, "\(spelling)")
        }
    }
}

#endif
