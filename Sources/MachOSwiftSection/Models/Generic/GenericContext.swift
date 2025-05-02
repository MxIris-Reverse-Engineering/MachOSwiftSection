//
//  GenericContext.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public struct GenericContext {
    public let offset: Int
    public let header: GenericContextDescriptorHeader
    public let parameters: [GenericParamDescriptor]
    public let requirements: [GenericRequirementDescriptor]
    public let typePacks: [GenericPackShapeDescriptor]
}