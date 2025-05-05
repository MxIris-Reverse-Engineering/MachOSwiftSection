//
//  OpaqueTypeDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol OpaqueTypeDescriptorProtocol: ContextDescriptorProtocol where Layout: OpaqueTypeDescriptorLayout {}
