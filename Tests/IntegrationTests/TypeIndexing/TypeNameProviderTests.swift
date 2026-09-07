#if os(macOS)

import Foundation
import MachOFixtureSupport
import MachOKit
import MachOSwiftSection
import SwiftInterface
import Testing
import TypeIndexing
@testable import MachOTestingSupport

/// Maintainer-run end-to-end for the TypeIndexing provider (evolution
/// proposal 0008): builds the fixture's interface with and without
/// `SwiftInterfaceBuilderTypeNameProvider` attached and prints every line the
/// provider changed, plus any `__C.` reference left unresolved.
///
/// The first run per SDK build generates the linked modules' interfaces
/// through sourcekitd (tens of seconds) and caches the extraction under
/// `Application Support/MachOSwiftSection/SDKIndexer/`.
final class TypeNameProviderMachOFileTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @available(macOS 13.0, *)
    private func buildInterface(resolvingCModuleNames: Bool) async throws -> String {
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(indexConfiguration: .init(), printConfiguration: .init()),
            eventHandlers: [],
            in: machOFile
        )
        if resolvingCModuleNames {
            let providerDependencies = SwiftInterfaceBuilderDependencies(machO: machOFile, searchPaths: [.systemDyldSharedCache])
            if let typeNameProvider = SwiftInterfaceBuilderTypeNameProvider(machO: machOFile, dependencies: providerDependencies) {
                builder.addExtraDataProvider(typeNameProvider)
            } else {
                print("provider unavailable: no build-version command mapping to a known SDK platform")
            }
        }
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    @MainActor
    @Test func resolvedCModuleNames() async throws {
        guard #available(macOS 13.0, *) else {
            print("skipped: requires macOS 13")
            return
        }
        let baselineInterface = try await buildInterface(resolvingCModuleNames: false)
        let resolvedInterface = try await buildInterface(resolvingCModuleNames: true)

        let baselineLines = baselineInterface.components(separatedBy: "\n")
        let resolvedLines = resolvedInterface.components(separatedBy: "\n")
        print("baseline lines: \(baselineLines.count), resolved lines: \(resolvedLines.count)")

        for (baselineLine, resolvedLine) in zip(baselineLines, resolvedLines) where baselineLine != resolvedLine {
            print("- \(baselineLine.trimmingCharacters(in: .whitespaces))")
            print("+ \(resolvedLine.trimmingCharacters(in: .whitespaces))")
        }

        let unresolvedLines = resolvedLines.filter { $0.contains("__C.") || $0.contains("__ObjC.") }
        print("unresolved __C references: \(unresolvedLines.count)")
        for unresolvedLine in unresolvedLines {
            print("  \(unresolvedLine.trimmingCharacters(in: .whitespaces))")
        }
    }
}

#endif
