//
//  TypeContextDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public protocol TypeContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
    var accessFunctionPtr: RelativeOffset { get }
    var fieldDescriptor: RelativeDirectPointer<FieldDescriptor> { get }
}
