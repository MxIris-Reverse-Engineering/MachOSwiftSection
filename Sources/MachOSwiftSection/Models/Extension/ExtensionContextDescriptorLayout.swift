//
//  ExtensionContextDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//


public protocol ExtensionContextDescriptorLayout: ContextDescriptorLayout {
    var extendedContext: RelativeDirectPointer<MangledName?> { get }
}
