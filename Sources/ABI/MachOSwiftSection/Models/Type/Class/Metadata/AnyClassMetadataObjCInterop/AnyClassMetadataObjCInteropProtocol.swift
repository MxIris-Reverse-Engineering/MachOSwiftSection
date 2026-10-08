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

// MARK: - Deprecated Mach-O and pointer forms

extension AnyClassMetadataObjCInteropProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: asFinalClassMetadata(in: machO.context).")
    public func asFinalClassMetadata(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassMetadataObjCInterop {
        try asFinalClassMetadata(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: superclass(in: machO.context).")
    public func superclass(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> AnyClassMetadataObjCInterop? {
        try superclass(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: asFinalClassMetadata(in: .inProcess).")
    public func asFinalClassMetadata() throws -> ClassMetadataObjCInterop {
        try asFinalClassMetadata(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: superclass(in: .inProcess).")
    public func superclass() throws -> AnyClassMetadataObjCInterop? {
        try superclass(in: InProcessContext.shared)
    }
}
