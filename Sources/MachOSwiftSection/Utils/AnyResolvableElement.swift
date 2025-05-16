//
//  AnyResolvableElement.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//


public struct AnyResolvableElement: Resolvable {
    public let wrappedValue: any Resolvable
}
