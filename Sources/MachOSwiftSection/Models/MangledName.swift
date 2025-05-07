//
//  MangledName.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit
import Foundation

public struct MangledName: ResolvableElement {
    public let tokens: [String]

    public let startOffset: Int
    
    public let endOffset: Int
    
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> MangledName {
        try machO.readSymbolicMangledName(at: fileOffset)
    }

    public func stringValue() -> String {
        return tokens.joined(separator: "")
    }
}
