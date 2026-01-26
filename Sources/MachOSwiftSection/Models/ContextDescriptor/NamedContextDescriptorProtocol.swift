import MachOKit
import MachOFoundation

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> String {
        try layout.name.resolve(from: offset + layout.offset(of: .name), in: machO)
    }

    public func mangledName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.name.resolveAny(from: offset + layout.offset(of: .name), in: machO)
    }

    public func name() throws -> String {
        try layout.name.resolve(from: layout.pointer(from: asPointer, of: .name))
    }

    public func mangledName() throws -> MangledName {
        try layout.name.resolveAny(from: layout.pointer(from: asPointer, of: .name))
    }
}

// MARK: - ReadingContext Support

extension NamedContextDescriptorProtocol {
    public func name<Context: ReadingContext>(in context: Context) throws -> String {
        let baseAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        return try layout.name.resolve(at: baseAddress, in: context)
    }

    public func mangledName<Context: ReadingContext>(in context: Context) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        return try layout.name.resolveAny(at: baseAddress, in: context)
    }
}
