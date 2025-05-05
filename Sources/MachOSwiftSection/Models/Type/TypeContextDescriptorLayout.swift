//
//  TypeContextDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public protocol TypeContextDescriptorLayout: NamedContextDescriptorLayout {
    var accessFunctionPtr: RelativeOffset { get }
    var fieldDescriptor: RelativeDirectPointer<FieldDescriptor> { get }
}
