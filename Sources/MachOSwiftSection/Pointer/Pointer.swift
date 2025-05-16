//
//  Pointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit

public struct Pointer<Pointee: ResolvableElement>: RelativeIndirectType, PointerProtocol {
    public let address: UInt64
}

extension Pointer: ResolvableElement where Pointee: ResolvableElement {}

public typealias RawPointer = Pointer<AnyResolvableElement>
