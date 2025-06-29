import MachOKit
import MachOMacro
import MachOFoundation

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension NamedContextDescriptorProtocol {
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(from: offset + layout.offset(of: .name), in: machOFile)
    }
    
    public func mangledName(in machOFile: MachOFile) throws -> MangledName {
        try layout.name.resolveAny(from: offset + layout.offset(of: .name), in: machOFile)
    }
}
