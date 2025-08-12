import Foundation
import Testing
import Demangle
@testable import MachOTestingSupport
import MachOSwiftSection

final class OpaqueTypeTests: DyldCacheTests {
    @Test func opaqueTypes() async throws {
        for contextDescriptor in try machOFileInSubCache.swift.contextDescriptors {
            switch contextDescriptor {
            case let .opaqueType(opaqueTypeDescriptor):
                let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machOFileInSubCache)
                for underlyingTypeArgumentMangledName in opaqueType.underlyingTypeArgumentMangledNames {
                    let node = try MetadataReader.demangleType(for: underlyingTypeArgumentMangledName, in: machOFileInSubCache)
                    node.print(using: .interface).print()
                }
                print("--------------------")
            default:
                break
            }
        }
    }
}
