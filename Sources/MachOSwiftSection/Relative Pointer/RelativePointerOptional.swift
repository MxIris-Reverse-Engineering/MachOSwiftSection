//
//  RelativePointerOptional.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


protocol RelativePointerOptional: ExpressibleByNilLiteral {
    associatedtype Wrapped
}

extension Optional: RelativePointerOptional {}
