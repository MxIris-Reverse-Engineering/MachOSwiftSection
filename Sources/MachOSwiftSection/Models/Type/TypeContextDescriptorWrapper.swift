import MachOKit
import MachOFoundation
import MachOMacro

public enum TypeContextDescriptorWrapper {
    case `enum`(EnumDescriptor)
    case `struct`(StructDescriptor)
    case `class`(ClassDescriptor)

    public var contextDescriptor: any ContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }

    public var namedContextDescriptor: any NamedContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }

    public var typeContextDescriptor: any TypeContextDescriptorProtocol {
        switch self {
        case .enum(let enumDescriptor):
            return enumDescriptor
        case .struct(let structDescriptor):
            return structDescriptor
        case .class(let classDescriptor):
            return classDescriptor
        }
    }
    
    public func parent<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try contextDescriptor.parent(in: machO)
    }

    public func genericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> GenericContext? {
        return try contextDescriptor.genericContext(in: machO)
    }
}


extension TypeContextDescriptorWrapper: Resolvable {
    public enum ResolutionError: Error {
        case invalidTypeContextDescriptor
    }
    public static func resolve<MachO>(from offset: Int, in machO: MachO) throws -> Self where MachO : MachORepresentableWithCache, MachO : MachOReadable {
        let contextDescriptor: ContextDescriptor = try machO.readWrapperElement(offset: offset)
        switch contextDescriptor.flags.kind {
        case .class:
            return try .class(machO.readWrapperElement(offset: offset))
        case .enum:
            return try .enum(machO.readWrapperElement(offset: offset))
        case .struct:
            return try .struct(machO.readWrapperElement(offset: offset))
        default:
            throw ResolutionError.invalidTypeContextDescriptor
        }
    }
    
    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        do {
            return try resolve(from: offset, in: machO) as Self
        } catch {
            print("Error resolving ContextDescriptorWrapper: \(error)")
            return nil
        }
    }
}
