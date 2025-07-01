import Foundation
import Testing
@testable import MachOSwiftSection
@testable import MachOTestingSupport


final class GenericContextTests: DyldCacheTests {
    override class var cacheImageName: MachOImageName { .SwiftUI }
    
    
    
    @Test func genericContexts() async throws {
        let typeDescriptors = try machOFileInCache.swift.typeContextDescriptors

        for typeDescriptor in typeDescriptors {
            guard case .type(let type) = typeDescriptor else {
                continue
            }
            switch type {
            case .enum(let descriptor):
                if let genericContext = try descriptor.typeGenericContext(in: machOFileInCache) {
                    print(genericContext.parameters)
                }
            case .struct(let descriptor):
                if let genericContext = try descriptor.typeGenericContext(in: machOFileInCache) {
                    print(genericContext.parameters)
                }
            case .class(let descriptor):
                if let genericContext = try descriptor.typeGenericContext(in: machOFileInCache) {
                    print(genericContext.parameters)
                }
            }
        }
    }
}
