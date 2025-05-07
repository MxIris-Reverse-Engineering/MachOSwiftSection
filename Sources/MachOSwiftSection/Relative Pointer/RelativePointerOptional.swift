//
//  RelativePointerOptional.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public protocol RelativePointerOptional: ExpressibleByNilLiteral {
    associatedtype Wrapped
    static func makeOptional(from wrappedValue: Wrapped) -> Self
}

extension Optional: RelativePointerOptional {
    public static func makeOptional(from wrappedValue: Wrapped) -> Self {
        return .some(wrappedValue)
    }
}