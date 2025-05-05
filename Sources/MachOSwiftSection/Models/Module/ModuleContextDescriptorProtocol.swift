//
//  ModuleContextDescriptorProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/5.
//

import MachOKit

public protocol ModuleContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: ModuleContextDescriptorLayout {}
