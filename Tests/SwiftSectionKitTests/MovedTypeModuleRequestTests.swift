#if os(macOS)

import Foundation
import Testing
import SwiftSectionKit
import SwiftSectionFixtureSupport

/// `resolvesMovedTypeModules` on the `interface` request (evolution proposal
/// `moved-swift-type-modules`): off by default, the product spells a moved
/// Swift type as its mangling does; on, as this Mac's SDK declares it. Reads
/// the SDK's textual interfaces only, no sourcekitd.
@Suite
struct MovedTypeModuleRequestTests {
    private static func fixture() throws -> MachOSource {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "MovedTypeModuleRequestFixture",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "MovedTypeModuleRequestFixture.swift", contents: """
            import Foundation
            public final class FixtureAnchor {}
            public struct Holder {
                public var width: CGFloat
                public init(width: CGFloat) { self.width = width }
            }
            """)],
            arguments: ["-swift-version", "5", "-target", "arm64-apple-macosx15.0"]
        )
        return .file(path: libraryURL.path, architecture: nil)
    }

    private static func interface(resolvesMovedTypeModules: Bool) async throws -> String {
        let output = RecordingOutput()
        try await InterfaceRequest(source: fixture(), resolvesMovedTypeModules: resolvesMovedTypeModules).run(output: output, environment: .testing)
        let declarations = output.products.compactMap { product in
            if case .declarations(let semanticString) = product { semanticString.string } else { nil }
        }
        return try #require(declarations.only)
    }

    @Test
    func interfaceRequestResolvesMovedTypeModulesOnlyWhenAsked() async throws {
        let unresolvedInterface = try await Self.interface(resolvesMovedTypeModules: false)
        #expect(unresolvedInterface.contains("var width: CoreGraphics.CGFloat"))
        let resolvedInterface = try await Self.interface(resolvesMovedTypeModules: true)
        #expect(resolvedInterface.contains("var width: CoreFoundation.CGFloat"))
        #expect(!resolvedInterface.contains("CoreGraphics.CGFloat"))
    }
}

#endif
