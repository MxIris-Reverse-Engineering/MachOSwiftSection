import Foundation
import MachOKit

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

extension TypeContextDescriptorProtocol {
    func _offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let memberOffset = switch keyPath {
        case \.flags:
            0
        case \.parent:
            4
        case \.name:
            8
        case \.accessFunctionPtr:
            12
        case \.fieldDescriptor:
            16
        default:
            fatalError("KeyPath: \(keyPath) not supported")
        }
        return offset + memberOffset
    }

    public func fieldDescriptor(in machOFile: MachOFile) throws -> FieldDescriptor {
        try layout.fieldDescriptor.resolve(from: _offset(of: \.fieldDescriptor).cast(), in: machOFile)
    }

//    public func genericContext(in machO: MachOFile) throws -> GenericContext? {
//        return try typeGenericContext(in: machO)
//    }
    
    public func typeGenericContext(in machOFile: MachOFile) throws -> TypeGenericContext? {
        return try .init(contextDescriptor: self, in: machOFile)
    }
}

func align(address: UInt64, alignment: UInt64) -> UInt64 {
    (address + alignment - 1) & ~(alignment - 1)
}
