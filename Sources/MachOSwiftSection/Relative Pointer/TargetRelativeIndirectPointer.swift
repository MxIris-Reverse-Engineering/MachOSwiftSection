//
//  TargetRelativeIndirectPointer.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//


public struct TargetRelativeIndirectPointer<Pointee: ResolvableElement, Offset: FixedWidthInteger, IndirectType: RelativeIndirectType>: RelativeIndirectPointerProtocol where Pointee == IndirectType.Pointee {
    public typealias Element = Pointee
    public let relativeOffset: Offset
}
