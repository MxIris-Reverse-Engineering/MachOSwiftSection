//
//  TargetRelativeIndirectPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public struct TargetRelativeIndirectPointer<Pointee: Resolvable, Offset: FixedWidthInteger & SignedInteger, IndirectType: RelativeIndirectType>: RelativeIndirectPointerProtocol where Pointee == IndirectType.Resolved {
    public typealias Element = Pointee
    public let relativeOffset: Offset
}
