import Foundation
import MachOKit
import MachOBase

public protocol AnyClassMetadataObjCInteropProtocol: HeapMetadataProtocol where Layout: AnyClassMetadataObjCInteropLayout {}

extension AnyClassMetadataObjCInteropProtocol {
    public func asFinalClassMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassMetadataObjCInterop {
        try .resolve(from: offset, in: machO)
    }
    
    public func asFinalClassMetadata() throws -> ClassMetadataObjCInterop {
        try .resolve(from: asPointer)
    }
}

extension AnyClassMetadataObjCInteropProtocol {
    public func superclass(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve(in: machO)
    }
    
    public func superclass() throws -> AnyClassMetadataObjCInterop? {
        try layout.superclass.resolve()
    }

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
