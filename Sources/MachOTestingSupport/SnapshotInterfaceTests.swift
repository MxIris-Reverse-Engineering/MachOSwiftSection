import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface

@MainActor
package protocol SnapshotInterfaceTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SnapshotInterfaceTests {
    package var snapshotBuilderConfiguration: SwiftInterfaceBuilderConfiguration {
        SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: false
            ),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printTypeLayout: true
            )
        )
    }

    package func collectInterfaceString(in machO: MachOFile) async throws -> String {
        let builder = try SwiftInterfaceBuilder(
            configuration: snapshotBuilderConfiguration,
            eventHandlers: [],
            in: machO
        )
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }
}
