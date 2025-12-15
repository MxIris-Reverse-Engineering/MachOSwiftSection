import Foundation
import Testing
import Demangling
@testable import MachOTestingSupport
import MachOSwiftSection
@testable import SwiftDump
@_spi(Internals) import MachOSymbols
@testable import SwiftInspection

protocol OpaqueTypeTests {}

extension OpaqueTypeTests {
    func opaqueTypes<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        let symbols = SymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machO)
        for symbol in symbols {
            guard symbol.offset > 0 else { continue }
            print("Offset:", symbol.offset)
            print("Demangled:")
            symbol.demangledNode.print(using: .default).print()
            symbol.demangledNode.description.print()
            let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: symbol.offset, in: machO)
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
            print("Current Requirements:")
            for requirement in try opaqueType.requirements(in: machO) {
                let requirementString = try await requirement.dump(using: .default, in: machO).string
                requirementString.print()
                if let node = try MetadataReader.buildGenericSignature(for: [requirement], in: machO) {
                    node.description.print()
                }
            }
            print("Underlying Types:")
            for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                let node = try MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machO)
                node.description.print()
                node.print(using: .default).print()
            }
            print("--------------------")
        }

//        try print(OpaqueType(descriptor: .resolve(from: 895065692, in: machO), in: machO))
//        try await print(MetadataReader.demangleSymbol(for: Symbol.resolve(from: 895065692, in: machO), in: machO)?.print())
    }
}

final class OpaqueTypeDyldCacheTests: DyldCacheTests, OpaqueTypeTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .SwiftUI }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOFileInCache)
    }
}

final class OpaqueTypeMachOFileTests: MachOFileTests, OpaqueTypeTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOFile)
    }
}

final class OpaqueTypeMachOImageTests: MachOImageTests, OpaqueTypeTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOImage)
    }
}
