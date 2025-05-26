import MachOKit
import MachOSwiftSectionMacro

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension NamedContextDescriptorProtocol {
    //@MachOImageGenerator
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(from: offset + layout.offset(of: .name), in: machOFile)
    }
    
    
    //@MachOImageGenerator
    public func fullname(in machOFile: MachOFile) throws -> String {
        var name = try name(in: machOFile)
        var parent = try parent(in: machOFile)
        findParent: while let currnetParent = parent {
            switch currnetParent {
            case .symbol(let unsolvedSymbol):
                name = unsolvedSymbol.stringValue + "." + name
                break findParent
            case .element(let element):
                if let parentName = try element.name(in: machOFile) {
                    name = parentName + "." + name
                }
                parent = try element.contextDescriptor.parent(in: machOFile)
            }

        }
        return name
    }
}
