import Foundation

public func _getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
    try Swift._getTypeByMangledNameInContext(UnsafePointer<UInt8>(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericContext: nil, genericArguments: nil)
}

public func _getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
    try Swift._getTypeByMangledNameInEnvironment(UnsafePointer<UInt8>(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericEnvironment: nil, genericArguments: nil)
}
