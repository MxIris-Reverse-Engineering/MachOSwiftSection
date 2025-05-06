//
//  ContextDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public protocol ContextDescriptorLayout {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeDirectPointer<ContextDescriptorWrapper?> { get }
}
