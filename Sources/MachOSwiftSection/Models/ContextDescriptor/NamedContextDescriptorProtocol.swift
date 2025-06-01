import MachOKit
import MachOSwiftSectionMacro

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension NamedContextDescriptorProtocol {
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(from: offset + layout.offset(of: .name), in: machOFile)
    }
    
    
}
