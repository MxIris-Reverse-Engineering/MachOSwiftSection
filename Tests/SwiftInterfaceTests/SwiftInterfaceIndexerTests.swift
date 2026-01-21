import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@_spi(Support) @testable import SwiftInterface
import Dependencies
@_private(sourceFile: "SymbolIndexStore.swift") @_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

final class SwiftInterfaceIndexerTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }
    
    @Test func conformingTypesByProtocolName() async throws {
        let machO = machOImage

        let indexer = SwiftInterfaceIndexer<MachOImage>(in: machO)

        try await indexer.prepare()

        for (protocolName, conformingTypes) in indexer.conformingTypesByProtocolName {
            guard !conformingTypes.isEmpty else { continue }
            protocolName.name.print()
            "".print()
            "Conforming Types:".print()
            for conformingType in conformingTypes {
                conformingType.name.print()
            }

            "-------------".print()
        }
    }
}
