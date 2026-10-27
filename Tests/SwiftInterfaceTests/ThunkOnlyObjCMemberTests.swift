import Foundation
import Testing
import MachOKit
import MachOKitExtensions
import MachOFoundation
import MachOSwiftSection
import SwiftDeclarationRendering
import SwiftInterface
@_spi(Internals) import MachOSymbols
@testable import MachOTestingSupport

/// Members whose implementation symbol the optimizer deleted while another of
/// their entry points survived (evolution proposal `thunk-only-objc-members`):
/// an `@objc` member whose body was inlined into its Objective-C thunk, and a
/// class initializer whose allocating entry point was inlined into its
/// callers. The interface built every member from its implementation symbol
/// and printed none of these; Xcode 27.2's `Xcode Service` lost 22 `@objc`
/// members and 9 initializers that way (issues #137 and #138). Each is now
/// built from the entry point the image kept.
///
/// The unoptimized build of the same source is the independent truth: it
/// keeps every entry point, so whatever the optimized build prints must be
/// what the unoptimized one prints.
@Suite(.serialized, ExclusiveImageAccess(ThunkOnlyMemberFixture.moduleName))
struct ThunkOnlyObjCMemberTests {
    private static let typeQualifiedNamePrefix = ThunkOnlyMemberFixture.moduleName + "."

    /// The header lines of the blocks the fixture declares, each the start of
    /// a line in the interface.
    private static let blockHeaders = [
        "class ThunkOnlyWidget: ",
        "class GenericThunkOnlyWidget<",
        "class InitializingEntryOnlyHolder",
        "extension __C.NSObject",
    ]

    private func interface(of machO: some MachOFieldLayoutRenderable, printsMemberAddresses: Bool = false) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printMemberAddress = printsMemberAddresses
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machO)
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

    /// The declaration lines of a block: every line after the header that is
    /// not a comment, an accessor keyword, a closing brace or blank.
    private func declarations(in block: String) -> [String] {
        block.split(separator: "\n").dropFirst().compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//"), trimmedLine != "}", trimmedLine != "get", trimmedLine != "set" else { return nil }
            return trimmedLine
        }
    }

    // MARK: - The premise

    /// What the optimized build lost: `isEqual(_:)` has no Swift entry point
    /// beside its thunk, `init(values:)` no allocating entry point beside its
    /// initializing one. Without this, the tests below could pass on a
    /// compiler that stopped deleting the entry points.
    @Test func optimizedBuildKeepsOnlyTheThunkOrTheInitializingEntryPoint() throws {
        let machOFile = try ThunkOnlyMemberFixture.machOFile(.wholeModuleOptimized)
        let symbolIndexStore = SymbolIndexStore.shared
        let widgetName = Self.typeQualifiedNamePrefix + "ThunkOnlyWidget"
        let functionNames = symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: widgetName, in: machOFile).map(\.name)
        #expect(!functionNames.contains { $0.contains("7isEqual") }, "\(functionNames)")
        let thunkNames = symbolIndexStore.objcThunkMemberSymbols(of: .function(inExtension: false, isStatic: false), for: widgetName, in: machOFile).map(\.name)
        #expect(thunkNames.contains { $0.hasSuffix("7isEqualySbypSgFTo") }, "\(thunkNames)")

        let holderName = Self.typeQualifiedNamePrefix + "InitializingEntryOnlyHolder"
        #expect(symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: holderName, in: machOFile).isEmpty)
        #expect(symbolIndexStore.memberSymbols(of: .constructor(inExtension: false), for: holderName, in: machOFile).count == 1)
    }

    /// The thunk index holds the thunk's own symbol, and nothing it holds is
    /// a member symbol of its own: the unoptimized build files `isEqual(_:)`
    /// in the member index (its Swift entry point) and in the thunk index
    /// (its thunk), each under its own name.
    @Test func thunkIndexHoldsTheThunksOwnSymbol() throws {
        let machOFile = try ThunkOnlyMemberFixture.machOFile(.unoptimized)
        let symbolIndexStore = SymbolIndexStore.shared
        let widgetName = Self.typeQualifiedNamePrefix + "ThunkOnlyWidget"
        let implementationNames = symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: widgetName, in: machOFile).map(\.name)
        let thunkNames = symbolIndexStore.objcThunkMemberSymbols(of: .function(inExtension: false, isStatic: false), for: widgetName, in: machOFile).map(\.name)
        let implementationName = try #require(implementationNames.first { $0.hasSuffix("7isEqualySbypSgF") }, "\(implementationNames)")
        #expect(thunkNames.contains(implementationName + "To"), "\(thunkNames)")
        #expect(!implementationNames.contains { $0.hasSuffix("To") }, "\(implementationNames)")
        #expect(thunkNames.allSatisfy { $0.hasSuffix("To") }, "\(thunkNames)")
    }

    // MARK: - The interface

    /// Every block the fixture declares prints the same declarations from
    /// both builds. The order may differ — an unoptimized class gives its
    /// ObjC overrides vtable slots, which print first — so the declarations
    /// compare as sets.
    @Test(arguments: blockHeaders)
    func optimizedBuildDeclaresWhatTheUnoptimizedBuildDeclares(blockHeader: String) async throws {
        let unoptimizedInterface = try await interface(of: try ThunkOnlyMemberFixture.machOFile(.unoptimized))
        let optimizedInterface = try await interface(of: try ThunkOnlyMemberFixture.machOFile(.wholeModuleOptimized))
        let unoptimizedBlock = try #require(block(startingWith: blockHeader, in: unoptimizedInterface), "\(unoptimizedInterface)")
        let optimizedBlock = try #require(block(startingWith: blockHeader, in: optimizedInterface), "\(optimizedInterface)")
        #expect(Set(declarations(in: optimizedBlock)) == Set(declarations(in: unoptimizedBlock)), "unoptimized:\n\(unoptimizedBlock)\n\noptimized:\n\(optimizedBlock)")
    }

    /// The members as issue #137 expects them: `@objc`, and `override` where
    /// the ObjC method table ties the thunk to an ancestor's selector.
    @Test func thunkOnlyMembersPrintWithTheirObjCFacts() async throws {
        let optimizedInterface = try await interface(of: try ThunkOnlyMemberFixture.machOFile(.wholeModuleOptimized))
        let widgetBlock = try #require(block(startingWith: "class ThunkOnlyWidget: ", in: optimizedInterface), "\(optimizedInterface)")
        let widgetDeclarations = declarations(in: widgetBlock)
        #expect(widgetDeclarations.contains("@objc override init()"), "\(widgetBlock)")
        #expect(widgetDeclarations.contains("@objc override func isEqual(_: Any?) -> Swift.Bool"), "\(widgetBlock)")
        #expect(widgetDeclarations.contains("@objc override var description: Swift.String {"), "\(widgetBlock)")
        #expect(widgetDeclarations.contains("@objc func handleTick(_: Any?)"), "\(widgetBlock)")
        #expect(widgetDeclarations.contains("@objc func handleExtensionTick(_: Any?)"), "\(widgetBlock)")

        // No static class object, so no ObjC method table: `@objc` from the
        // thunk, no `override`.
        let genericBlock = try #require(block(startingWith: "class GenericThunkOnlyWidget<", in: optimizedInterface), "\(optimizedInterface)")
        let genericDeclarations = declarations(in: genericBlock)
        #expect(genericDeclarations.contains("@objc var description: Swift.String {"), "\(genericBlock)")
        #expect(genericDeclarations.contains("@objc init()"), "\(genericBlock)")

        let holderBlock = try #require(block(startingWith: "class InitializingEntryOnlyHolder", in: optimizedInterface), "\(optimizedInterface)")
        #expect(declarations(in: holderBlock).contains("init(values: [Swift.String])"), "\(holderBlock)")

        let extensionBlock = try #require(block(startingWith: "extension __C.NSObject", in: optimizedInterface), "\(optimizedInterface)")
        #expect(declarations(in: extensionBlock).contains("@objc func thunkOnlyFixtureHook()"), "\(extensionBlock)")
    }

    /// Only an initializer that has an `@objc` thunk of its own is `@objc`.
    /// An initializer's thunk names no member to match by, and every
    /// initializer of the class used to get the attribute as soon as one had a
    /// thunk: `init(tags:)` printed `@objc` beside `@objc override init()`, as
    /// `MenuBarLabelHostingView.init(rootView:)` did in Xcode Service.
    @Test(arguments: ThunkOnlyMemberFixture.Variant.allCases)
    func onlyAnInitializerWithAnObjCThunkIsObjC(variant: ThunkOnlyMemberFixture.Variant) async throws {
        let interface = try await interface(of: try ThunkOnlyMemberFixture.machOFile(variant))
        let widgetBlock = try #require(block(startingWith: "class ThunkOnlyWidget: ", in: interface), "\(interface)")
        let widgetDeclarations = declarations(in: widgetBlock)
        #expect(widgetDeclarations.contains("init(tags: [Swift.String])"), "\(widgetBlock)")
        #expect(widgetDeclarations.contains("@objc override init()"), "\(widgetBlock)")
    }

    /// A member built from its thunk is located at the thunk, the only code it
    /// has; an initializer built from its initializing entry point, there.
    @Test func standInMembersPrintTheAddressOfTheEntryPointTheImageKept() async throws {
        let machOFile = try ThunkOnlyMemberFixture.machOFile(.wholeModuleOptimized)
        let symbolIndexStore = SymbolIndexStore.shared
        let widgetName = Self.typeQualifiedNamePrefix + "ThunkOnlyWidget"
        let thunkSymbol = try #require(symbolIndexStore.objcThunkMemberSymbols(of: .function(inExtension: false, isStatic: false), for: widgetName, in: machOFile).first { $0.name.hasSuffix("7isEqualySbypSgFTo") })
        let holderName = Self.typeQualifiedNamePrefix + "InitializingEntryOnlyHolder"
        let initializerSymbol = try #require(symbolIndexStore.memberSymbols(of: .constructor(inExtension: false), for: holderName, in: machOFile).first)

        let optimizedInterface = try await interface(of: machOFile, printsMemberAddresses: true)
        let widgetBlock = try #require(block(startingWith: "class ThunkOnlyWidget: ", in: optimizedInterface), "\(optimizedInterface)")
        #expect(widgetBlock.contains("// Address: 0x\(machOFile.addressString(forOffset: thunkSymbol.offset))\n    @objc override func isEqual("), "\(widgetBlock)")
        let holderBlock = try #require(block(startingWith: "class InitializingEntryOnlyHolder", in: optimizedInterface), "\(optimizedInterface)")
        #expect(holderBlock.contains("// Address: 0x\(machOFile.addressString(forOffset: initializerSymbol.offset))\n    init(values: [Swift.String])"), "\(holderBlock)")
    }

    /// RuntimeViewer's path: the optimized image loaded into the process and
    /// read through `MachOImage` prints what the file prints.
    @Test(arguments: blockHeaders)
    func optimizedImageInProcessDeclaresWhatTheFileDeclares(blockHeader: String) async throws {
        let fileInterface = try await interface(of: try ThunkOnlyMemberFixture.machOFile(.wholeModuleOptimized))
        let imageInterface = try await interface(of: try ThunkOnlyMemberFixture.loadedOptimizedImage())
        let fileBlock = try #require(block(startingWith: blockHeader, in: fileInterface), "\(fileInterface)")
        let imageBlock = try #require(block(startingWith: blockHeader, in: imageInterface), "\(imageInterface)")
        #expect(Set(declarations(in: imageBlock)) == Set(declarations(in: fileBlock)), "file:\n\(fileBlock)\n\nimage:\n\(imageBlock)")
    }
}
