import Foundation
import Testing
@testable import SwiftInterface
import SourceKitD
import FoundationToolbox

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
