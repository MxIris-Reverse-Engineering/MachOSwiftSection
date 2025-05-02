//
//  GenericRequirementKind.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public enum GenericRequirementKind: UInt8 {
    case `protocol`
    case sameType
    case baseClass
    case sameConformance
    case sameShape
    case invertedProtocols
    case layout = 0x1F
}


