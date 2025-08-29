import Foundation
import Testing
@testable import SwiftInterface

final class SDKIndexerTests {
    
    
    @Test func index() async throws {
        let indexer = SDKIndexer(sdkRoot: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
        try await indexer.index()
        for module in indexer.modules {
            print(module)
        }
    }
    
}
