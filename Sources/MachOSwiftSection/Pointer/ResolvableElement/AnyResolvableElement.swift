//
//  AnyResolvableElement.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//


public struct AnyResolvableElement: ResolvableElement {
    public let wrappedValue: any ResolvableElement
}