//
//  MangledName.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit
import Foundation

public struct MangledName: ResolvableElement {
    public enum Element {
        public struct Lookup {
            enum Reference {
                case relative(RelativeReference)
                case absolute(AbsoluteReference)
            }

            struct RelativeReference {
                let kind: UInt8
                let relativeOffset: RelativeOffset
            }

            struct AbsoluteReference {
                let kind: UInt8
                let reference: UInt64
            }

            let offset: Int
            let reference: Reference
        }

        case string(String)
        case lookup(Lookup)
    }
    public let elements: [Element]

    public let startOffset: Int
    
    public let endOffset: Int
    
    public static func resolve(from fileOffset: Int, in machO: MachOFile) throws -> MangledName {
        try machO.readSymbolicMangledName(at: fileOffset)
    }

    public var lookupElements: [Element.Lookup] {
        elements.compactMap { if case let .lookup(lookup) = $0 { lookup } else { nil } }
    }
    
    public func stringValue() -> String {
        guard !elements.isEmpty else { return "" }
        var results: [String] = []
        for element in elements {
            switch element {
            case .string(let string):
                results.append(string)
            case .lookup(let lookup):
                switch lookup.reference {
                case .relative(let reference):
                    results.append(String(UnicodeScalar(reference.kind)))
                case .absolute(let reference):
                    results.append(String(UnicodeScalar(reference.kind)))
                }
            }
        }
        return results.joined(separator: "").insertTypeManglePrefix
    }
}
