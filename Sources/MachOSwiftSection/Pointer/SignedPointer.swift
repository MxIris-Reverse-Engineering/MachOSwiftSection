//
//  SignedPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/15.
//

import MachOKit

public struct SignedPointer<Pointee: ResolvableElement>: RelativeIndirectType, PointerProtocol {
    public let address: UInt64
}
