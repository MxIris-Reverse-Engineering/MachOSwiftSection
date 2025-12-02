import Foundation
import Testing
@testable import MachOTestingSupport
@testable import TypeIndexing

class SwiftInterfaceParserTests: DyldCacheTests, @unchecked Sendable {
    @Test func index() async throws {
        let indexer = try SwiftInterfaceParser(file: .init(moduleName: "SwiftUI", path: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"))
        try await indexer.index()
        for typeInfo in await indexer.typeInfos {
            print(typeInfo)
        }
    }
}
