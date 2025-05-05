//
//  StructDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public protocol StructDescriptorLayout: TypeContextDescriptorLayout {
    var numFields: UInt32 { get }
    var fieldOffsetVector: UInt32 { get }
}