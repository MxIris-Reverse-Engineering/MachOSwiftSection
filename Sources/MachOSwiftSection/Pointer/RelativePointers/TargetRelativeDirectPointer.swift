//
//  TargetRelativeDirectPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public struct TargetRelativeDirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger>: RelativeDirectPointerProtocol {
    public typealias Element = Pointee
    public let relativeOffset: Offset
}
