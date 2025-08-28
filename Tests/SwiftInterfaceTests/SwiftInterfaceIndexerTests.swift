import Foundation
import Testing
@testable import MachOTestingSupport
@testable import SwiftInterface

class SwiftInterfaceIndexerTests: DyldCacheTests {
    @Test func index() async throws {
        let indexer = try SwiftInterfaceIndexer(contents: .init(contentsOfFile: "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface", encoding: .utf8))
        indexer.index()
        for typeInfo in indexer.typeInfos {
            print(typeInfo)
        }
    }
}
