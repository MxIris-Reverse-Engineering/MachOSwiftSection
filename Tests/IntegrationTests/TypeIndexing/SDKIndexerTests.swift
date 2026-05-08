#if os(macOS)

import Foundation
import Testing
import SourceKitD
import FoundationToolbox
@testable import TypeIndexing

final class SDKIndexerTests {
    @Test func index() async throws {
        let indexer = SDKIndexer(platform: .macOS)
        indexer.cacheIndexes = true
        try await indexer.index()
        for module in indexer.modules {
            print(module.moduleName)
            for subModuleInterfaceFile in module.subModuleInterfaceFiles {
                print(subModuleInterfaceFile.moduleName)
            }
        }
    }
}

#endif
