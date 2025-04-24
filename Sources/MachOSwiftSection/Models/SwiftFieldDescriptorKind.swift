//
//  SwiftFieldDescriptorKind.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/4/24.
//


public enum SwiftFieldDescriptorKind: UInt16 {
    case `struct`
    case `class`
    case `enum`
    case multiPayloadEnum
    case `protocol`
    case classProtocol
    case objCProtocol
    case objCClass
    case unknown
}