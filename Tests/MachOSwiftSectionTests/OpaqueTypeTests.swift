import Foundation
import Testing
import Demangle
@testable import MachOTestingSupport
import MachOSwiftSection
@testable import SwiftDump

protocol OpaqueTypeTests {}

extension OpaqueTypeTests {
    func opaqueTypes<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        let symbols = SymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machO)
        for symbol in symbols {
            guard symbol.offset > 0 else { continue }
            symbol.demangledNode.print(using: .default).print()
            let opaqueTypeDescriptor = try OpaqueTypeDescriptor.resolve(from: symbol.offset, in: machO)
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
            if let genericContext = opaqueType.genericContext {
                print("Current Requirements:")
                let parentRequirementStrings = try genericContext.parentRequirements.flatMap { $0 }.map { try $0.dump(using: .default, in: machO).string }
                for requirement in genericContext.requirements {
                    let requirementString = try requirement.dump(using: .default, in: machO).string
                    if !parentRequirementStrings.contains(requirementString) {
                        requirementString.print()
                    }
                }
                
                print("Parent Requirements:")
                for (offset, requirements) in genericContext.parentRequirements.enumerated() {
                    print("Level:", offset)
                    for requirement in requirements {
                        try requirement.dump(using: .default, in: machO).string.print()
                    }
                }
            }
            for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                let node = try MetadataReader.demangle(for: underlyingTypeArgumentMangledName, in: machO)
                node.print(using: .default).print()
            }
            print("--------------------")
        }
    }
}

final class OpaqueTypeDyldCacheTests: DyldCacheTests, OpaqueTypeTests {
    override class var cacheImageName: MachOImageName { .SwiftUICore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOFileInMainCache)
    }
}

final class OpaqueTypeMachOImageTests: MachOImageTests, OpaqueTypeTests {
    override class var imageName: MachOImageName { .SwiftUICore }

    @MainActor
    @Test func opaqueTypes() async throws {
        try await opaqueTypes(in: machOImage)
    }
}
