//
//  ProtocolDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//


public protocol ProtocolDescriptorLayout: NamedContextDescriptorLayout {
    var numRequirementsInSignature: UInt32 { get }
    var numRequirements: UInt32 { get }
    var associatedTypes: RelativeDirectPointer<String> { get }
}