import Foundation
import Testing
@testable import MachOTestingSupport
@testable import TypeIndexing

class SwiftInterfaceIndexerTests: DyldCacheTests {
    @Test func index() async throws {
        let indexer = try SwiftInterfaceIndexer(file: .init(moduleName: "SwiftUI", path: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"))
        try await indexer.index()
        for typeInfo in await indexer.typeInfos {
            print(typeInfo)
        }
    }
}



