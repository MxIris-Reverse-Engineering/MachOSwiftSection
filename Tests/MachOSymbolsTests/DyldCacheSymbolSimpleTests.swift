import Foundation
import Testing
@testable import Demangling
import MachOKit
import MachOFoundation
@testable import MachOTestingSupport
import Dependencies

#if !SILENT_TEST && os(macOS)

final class DyldCacheSymbolSimpleTests: DyldCacheSymbolTests, @unchecked Sendable {
    @MainActor
    @available(macOS 13.0, *)
    @Test func writeSymbolsToDesktop() async throws {
        var string = ""
        let imageName: MachOImageName = .SwiftUICore
        let symbols = try await symbols(for: imageName)
        for symbol in symbols {
            let node = try demangleAsNode(symbol.stringValue)
            guard !symbol.stringValue.hasSuffix("$delayInitStub") else { continue }
            string += "---------------------------------------"
            string += "\n"
            string += symbol.stringValue
            string += "\n"
            string += node.print(using: .default)
            string += "\n"
            string += node.description
            string += "\n"
            string += "---------------------------------------"
            string += "\n"
            string += "\n"
        }

        let directoryURL = URL.documentsDirectory.appending(component: "SwiftSymbolExpanded")
        try directoryURL.createDirectoryIfNeeded()

        try string.write(to: directoryURL.appending(components: "\(imageName.rawValue).txt"), atomically: true, encoding: .utf8)
    }

    @Test func demangle() async throws {
        try demangleAsNode("_TtCs12_SwiftObject").print().print()
    }
}

#endif
