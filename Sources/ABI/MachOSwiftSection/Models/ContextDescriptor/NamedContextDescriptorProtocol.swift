import MachOKit
import MachOBase

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name(in context: some ReadingContext) throws -> String {
        let baseAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        return try layout.name.resolve(at: baseAddress, in: context)
    }

    public func mangledName(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        return try layout.name.resolveAny(at: baseAddress, in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension NamedContextDescriptorProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: name(in: machO.context).")
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try name(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: machO.context).")
    public func mangledName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: name(in: .inProcess).")
    public func name() throws -> String {
        try name(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledName(in: .inProcess).")
    public func mangledName() throws -> MangledName {
        try mangledName(in: InProcessContext.shared)
    }
}
