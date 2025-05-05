//
//  NamedContextDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//


public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}