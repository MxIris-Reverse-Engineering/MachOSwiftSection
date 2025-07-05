import MachOKit
import MachOMacro
import MachOFoundation

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> String {
        try layout.name.resolve(from: offset + layout.offset(of: .name), in: machO)
    }
    
    public func mangledName<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> MangledName {
        try layout.name.resolveAny(from: offset + layout.offset(of: .name), in: machO)
    }
}
