import Foundation
import MachOKit
import MachOBase

public protocol AnyClassMetadataObjCInteropProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataObjCInteropLayout {}

extension AnyClassMetadataObjCInteropProtocol {
    public var isPureObjC: Bool {
        !isTypeMetadata
    }

    public var isTypeMetadata: Bool {
        layout.data & 2 != 0
    }
}

// MARK: - ReadingContext Support

extension AnyClassMetadataObjCInteropProtocol {
    public func asFinalClassMetadata(in context: some ReadingContext) throws -> ClassMetadataObjCInterop {
        try .resolve(at: try context.addressFromOffset(offset), in: context)
    }

    public func superclass(in context: some ReadingContext) throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve(in: context)
    }
}
