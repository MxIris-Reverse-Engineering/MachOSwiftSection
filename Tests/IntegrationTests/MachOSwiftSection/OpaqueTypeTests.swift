import Foundation
import MachOResolving
import Testing
import SwiftDeclarationRendering
import Demangling
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport
import MachOSwiftSection
@testable import SwiftDump
@_spi(Internals) import SwiftSymbols
@testable @_spi(Internals) import SwiftInspection
import Semantic

protocol OpaqueTypeTests {}

extension OpaqueTypeTests {
    func opaqueTypes(in machO: some MachOFieldLayoutRenderable) async throws {
        let symbols = SwiftSymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machO)
        for symbol in symbols {
            guard symbol.offset > 0 else { continue }
            print("Offset:", symbol.offset)
            print("Demangled:")
            await symbol.demangledNode.print(using: .default).print()
            symbol.demangledNode.description.print()
            let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(at: symbol.offset, in: machO.context)
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO.context)
            print("Current Requirements:")
            for requirement in try opaqueType.requirements(in: machO) {
                let requirementString = try await requirement.dump(using: .default, in: machO.context).string
                requirementString.print()
                if let node = try SymbolicDemangler.buildGenericSignature(for: [requirement], in: machO.context) {
                    node.description.print()
                }
            }
            print("Underlying Types:")
            for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                let node = try SymbolicDemangler.demangleType(for: underlyingTypeArgumentMangledName, in: machO.context)
                node.description.print()
                await node.print(using: .default).print()
            }
            print("--------------------")
        }
    }
}

final class OpaqueTypeDyldCacheTests: DyldCacheTests, nonisolated OpaqueTypeTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .SwiftUI }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOFileInCache)
    }

    @Test func test() async throws {
        let machO = machOFileInCache
        print(machO.startOffset)
        try print(OpaqueType(descriptor: .resolve(at: 895065692, in: machO.context), in: machO.context))
        print(machO.symbols(offset: 895065692) as Symbols?)
    }
}

final class OpaqueTypeMachOFileTests: MachOFileTests, nonisolated OpaqueTypeTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOFile)
    }
}

final class OpaqueTypeMachOImageTests: MachOImageTests, nonisolated OpaqueTypeTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOImage)
    }
}
