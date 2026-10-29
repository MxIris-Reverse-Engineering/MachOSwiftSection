import Foundation
import Testing
import MachOKit
import MachOFoundation
import SwiftDeclarationRendering
import SwiftDiffing
import SwiftInterface
@_spi(Internals) import MachOSymbols
@testable import MachOTestingSupport

/// A member an image declares on a type another image defines, with no
/// extension context in its mangling (evolution proposal
/// `image-group-evolution`). SwiftUI declares such members on the types
/// SwiftUICore defines under `@_originallyDefinedIn(module: "SwiftUI", …)`:
/// `Text.accessibilityTextContentType(_:)` is
/// `$s7SwiftUI4TextV013accessibilityC11ContentType…`, the same shape as a
/// member declared in the type's own body. The index gathered non-extension
/// members only for the types the indexed image defines, so these belonged
/// to no definition: SwiftUI's dump, interface and ABI snapshot left them
/// out. They now read as members of an extension of their type, beside the
/// members of a cross-module extension, whose mangling names the extension.
@Suite(.serialized, ExclusiveImageAccess(ImageGroupFixture.moduleName))
struct MembersOfAnotherImagesTypeTests {
    /// `ImageGroupFixture` in 2.0, where `Gauge` lives in the core image and
    /// the module's own image declares `calibrated()` and `standard` on it.
    private func splitModuleImage() throws -> MachOFile {
        try ImageGroupFixture.image(named: ImageGroupFixture.moduleName, atVersion: 1)
    }

    private func interface(of machO: some MachOFieldLayoutRenderable) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: SwiftInterfaceBuilderConfiguration(), eventHandlers: [], in: machO)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The block whose header line STARTS with `prefix`, through its closing
    /// brace at the same indentation.
    private func block(startingWith prefix: String, in interface: String) -> String? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[start...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    /// The premise: the image indexes `calibrated()` as a member of `Gauge`
    /// declared outside any extension — the shape that had no definition to
    /// land in. Without it, the tests below could pass on a compiler that
    /// started naming the extension.
    @Test func theMembersManglingNamesNoExtension() throws {
        let machOFile = try splitModuleImage()
        let gaugeName = "\(ImageGroupFixture.moduleName).Gauge"
        let functionNames = SymbolIndexStore.shared.memberSymbols(of: .function(inExtension: false, isStatic: false), for: gaugeName, in: machOFile).map(\.name)
        #expect(functionNames.contains { $0.contains("10calibrated") }, "\(functionNames)")
    }

    @Test("a member declared on another image's type prints in an extension of that type")
    func membersOfAnotherImagesTypePrintInAnExtension() async throws {
        let interface = try await interface(of: try splitModuleImage())
        let gaugeExtension = try #require(block(startingWith: "extension \(ImageGroupFixture.moduleName).Gauge", in: interface), "\(interface)")
        #expect(gaugeExtension.contains("func calibrated() -> Swift.Int"), "\(gaugeExtension)")
        #expect(gaugeExtension.contains("static var standard: \(ImageGroupFixture.moduleName).Gauge"), "\(gaugeExtension)")
    }

    @Test("a member of a cross-module extension keeps printing in its extension")
    func crossModuleExtensionMembersKeepTheirExtension() async throws {
        let interface = try await interface(of: try splitModuleImage())
        let needleExtension = try #require(block(startingWith: "extension \(ImageGroupFixture.coreModuleName).Needle", in: interface), "\(interface)")
        #expect(needleExtension.contains("func sweep() -> Swift.Int"), "\(needleExtension)")
    }

    @Test("the image's ABI snapshot carries the members declared on another image's type")
    func snapshotCarriesMembersOfAnotherImagesType() async throws {
        let builder = SwiftDiffableInterfaceBuilder(in: try splitModuleImage())
        try await builder.prepare()
        let gaugeExtensionSignatures = builder.snapshot().typeExtensions
            .filter { $0.name == "\(ImageGroupFixture.moduleName).Gauge" }
            .flatMap(\.members)
            .map(\.signature)
        #expect(gaugeExtensionSignatures.contains { $0.contains("calibrated()") }, "\(gaugeExtensionSignatures)")
        #expect(gaugeExtensionSignatures.contains { $0.contains("standard") }, "\(gaugeExtensionSignatures)")
    }
}
