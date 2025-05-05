//
//  EnumDescriptorLayout.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/3.
//


public protocol EnumDescriptorLayout: TypeContextDescriptorLayout {
    var numPayloadCasesAndPayloadSizeOffset: UInt32 { get }
    var numEmptyCases: UInt32 { get }
}