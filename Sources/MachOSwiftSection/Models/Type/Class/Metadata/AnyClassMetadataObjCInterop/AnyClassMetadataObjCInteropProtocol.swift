import Foundation
import MachOKit
import MachOFoundation

public protocol AnyClassMetadataObjCInteropProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataObjCInteropLayout {}

extension AnyClassMetadataObjCInteropProtocol {
    public func asFinalClassMetadata<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ClassMetadataObjCInterop {
        try .resolve(from: offset, in: machO)
    }
}
