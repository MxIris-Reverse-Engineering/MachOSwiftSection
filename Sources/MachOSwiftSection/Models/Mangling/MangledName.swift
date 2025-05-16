//
//  MangledName.swift
//  MachOSwiftSection
//
//  Created by JH on 2025/5/7.
//

import MachOKit
import Foundation

public struct MangledName {
    enum Element {
        struct Lookup: CustomStringConvertible {
            enum Reference {
                case relative(RelativeReference)
                case absolute(AbsoluteReference)
            }

            struct RelativeReference: CustomStringConvertible {
                let kind: UInt8
                let relativeOffset: RelativeOffset
                var description: String {
                    """
                    Kind: \(kind) RelativeOffset: \(relativeOffset)
                    """
                }
            }

            struct AbsoluteReference: CustomStringConvertible {
                let kind: UInt8
                let reference: UInt64
                var description: String {
                    """
                    Kind: \(kind) Address: \(reference)
                    """
                }
            }

            let offset: Int
            let reference: Reference

            var description: String {
                switch reference {
                case let .relative(relative):
                    "[Relative] FileOffset: \(offset) \(relative)"
                case let .absolute(absolute):
                    "[Absolute] FileOffset: \(offset) \(absolute)"
                }
            }
        }

        case string(String)
        case lookup(Lookup)
    }

    let elements: [Element]

    let startOffset: Int

    let endOffset: Int

    init(elements: [Element], startOffset: Int, endOffset: Int) {
        self.elements = elements
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
    
//    init(stringValue: String) {
//        self.init(elements: <#T##[Element]#>, startOffset: <#T##Int#>, endOffset: <#T##Int#>)
//    }
    
    var lookupElements: [Element.Lookup] {
        elements.compactMap { if case let .lookup(lookup) = $0 { lookup } else { nil } }
    }

    public func symbolStringValue() -> String {
        guard !elements.isEmpty else { return "" }
        return typeStringValue().insertManglePrefix
    }

    public func typeStringValue() -> String {
        guard !elements.isEmpty else { return "" }
        var results: [String] = []
        for element in elements {
            switch element {
            case let .string(string):
                results.append(string)
            case let .lookup(lookup):
                switch lookup.reference {
                case let .relative(reference):
                    results.append(String(UnicodeScalar(reference.kind)))
                case let .absolute(reference):
                    results.append(String(UnicodeScalar(reference.kind)))
                }
            }
        }
        return results.joined(separator: "")
    }

    public var isEmpty: Bool {
        return elements.isEmpty
    }
}

extension MangledName: Resolvable {
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> MangledName {
        var elements: [MangledName.Element] = []
        var currentOffset = fileOffset
        var currentString = ""
        while true {
            let value: UInt8 = try machOFile.readElement(offset: currentOffset)
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                currentOffset.offset(of: UInt8.self)
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: Int32 = try machOFile.readElement(offset: currentOffset + 1)
                let offset = Int(fileOffset + (currentOffset - fileOffset))
                elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: value, relativeOffset: reference + 1)))))
                currentOffset.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: UInt64 = try machOFile.readElement(offset: currentOffset + 1)
                let offset = Int(fileOffset + (currentOffset - fileOffset))
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(kind: value, reference: reference)))))
                currentOffset.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset.offset(of: UInt8.self)
        }

        return .init(elements: elements, startOffset: fileOffset, endOffset: currentOffset)
    }
}

extension MangledName: CustomStringConvertible {
    public var description: String {
        var lines: [String] = []
        lines.append("******************************************")
        for element in elements {
            var innerLines: [String] = []
            switch element {
            case let .string(string):
                innerLines.append("[String] \(string)")
            case let .lookup(lookup):
                innerLines.append(lookup.description)
            }
            lines.append(innerLines.joined(separator: "\n"))
        }
        lines.append("******************************************")
        return lines.joined(separator: "\n")
    }
}

public enum MangledNameKind {
    case type
    case symbol
}
