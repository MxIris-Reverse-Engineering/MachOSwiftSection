//
//  TypeContextDescriptorWrapper.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/14.
//


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
}