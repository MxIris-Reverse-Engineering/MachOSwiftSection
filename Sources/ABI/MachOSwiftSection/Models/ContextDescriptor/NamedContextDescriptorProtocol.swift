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
