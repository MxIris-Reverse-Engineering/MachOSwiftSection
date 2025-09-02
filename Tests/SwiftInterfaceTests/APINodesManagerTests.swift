import Foundation
import Testing
import APINotes
import Yams
@testable import SwiftInterface

struct APINotesManagerTests {
    @Test func index() async throws {
        let indexer = SDKIndexer(platform: .macOS)
        try await indexer.index()
        for apiNotesFile in indexer.apiNotesFiles {
            let data = try Data(contentsOf: .init(filePath: apiNotesFile.path))
            let module = try YAMLDecoder().decode(Module.self, from: data)
            dump(module)
        }
    }
}
