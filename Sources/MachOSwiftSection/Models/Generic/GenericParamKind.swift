//
//  GenericParamKind.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/2.
//


public enum GenericParamKind: UInt8 {
    case type
    case typePack
    case value
    case max = 0x3F
}