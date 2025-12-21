import Foundation
import MachOKit
import MachOFoundation
import FoundationToolbox

public enum Runtime {
    public static func _getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        try Swift._getTypeByMangledNameInContext(UnsafePointer<UInt8>(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericContext: nil, genericArguments: nil)
    }

    public static func _getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        try Swift._getTypeByMangledNameInEnvironment(UnsafePointer<UInt8>(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericEnvironment: nil, genericArguments: nil)
    }

    public static func _getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Any.Type? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return Swift._getTypeByMangledNameInContext(pointer, .init(mangledTypeName.size), genericContext: nil, genericArguments: nil)
    }

    public static func _getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Any.Type? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return Swift._getTypeByMangledNameInEnvironment(pointer, .init(mangledTypeName.size), genericEnvironment: nil, genericArguments: nil)
    }

}
