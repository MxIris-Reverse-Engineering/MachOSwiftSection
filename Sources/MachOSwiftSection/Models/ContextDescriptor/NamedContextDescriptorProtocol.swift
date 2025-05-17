import MachOKit

public protocol NamedContextDescriptorProtocol: ContextDescriptorProtocol where Layout: NamedContextDescriptorLayout {}

extension NamedContextDescriptorProtocol {
    public func name(in machOFile: MachOFile) throws -> String {
        try layout.name.resolve(from: 8 + offset, in: machOFile)
    }

    public func fullname(in machOFile: MachOFile) throws -> String {
        var name = try name(in: machOFile)
        var parent = try parent(in: machOFile)
        while let currnetParent = parent {
            switch currnetParent {
            case .symbol(let unsolvedSymbol):
                name = unsolvedSymbol.stringValue + "." + name
                break
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
