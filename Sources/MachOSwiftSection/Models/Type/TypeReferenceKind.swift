//
//  TypeReferenceKind.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/4.
//


public enum TypeReferenceKind: UInt8 {
    case directTypeDescriptor
    case indirectTypeDescriptor
    case directObjCClassName
    case indirectObjCClass
}