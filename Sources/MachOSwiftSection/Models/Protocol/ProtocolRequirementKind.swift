//
//  ProtocolRequirementKind.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/4.
//


public enum ProtocolRequirementKind: UInt8 {
    case baseProtocol
    case method
    case `init`
    case getter
    case setter
    case readCoroutine
    case modifyCoroutine
    case associatedTypeAccessFunction
    case associatedConformanceAccessFunction
}