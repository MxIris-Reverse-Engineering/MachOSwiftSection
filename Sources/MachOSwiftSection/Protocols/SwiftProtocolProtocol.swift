//
//  SwiftProtocolProtocol.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/4/23.
//

import Foundation
@_spi(Support) import MachOKit

public protocol SwiftProtocolProtocol: _FixupResolvable where LayoutField == SwiftProtocolLayoutField {
    associatedtype Layout: _SwiftProtocolLayoutProtocol
    
    var layout: Layout { get }
    var offset: Int { get }
    
    @_spi(Core)
    init(layout: Layout, offset: Int)
}

extension SwiftProtocolProtocol {
    public func name(in machO: MachOFile) -> String {
        let address = Int(layout.name) + layoutOffset(of: .name) + offset + machO.headerStartOffset
        return machO.fileHandle.readString(offset: numericCast(address))!
    }
}
