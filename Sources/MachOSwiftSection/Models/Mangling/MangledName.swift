import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct MangledName {
    package enum Element {
        package struct Lookup: CustomStringConvertible {
            package enum Reference {
                case relative(RelativeReference)
                case absolute(AbsoluteReference)
            }

            package struct RelativeReference: CustomStringConvertible {
                package let kind: UInt8
                package let relativeOffset: RelativeOffset
                package var description: String {
                    """
                    Kind: \(kind) RelativeOffset: \(relativeOffset)
                    """
                }
            }

            package struct AbsoluteReference: CustomStringConvertible {
                package let kind: UInt8
                package let reference: UInt64
                package var description: String {
                    """
                    Kind: \(kind) Address: \(reference)
                    """
                }
            }

            package let offset: Int
            package let reference: Reference

            package var description: String {
                switch reference {
                case .relative(let relative):
                    "[Relative] FileOffset: \(offset) \(relative)"
                case .absolute(let absolute):
                    "[Absolute] FileOffset: \(offset) \(absolute)"
                }
            }
        }

        case string(String)
        case lookup(Lookup)
    }

    package let elements: [Element]

    package let startOffset: Int

    package let endOffset: Int?

    package init(elements: [Element], startOffset: Int, endOffset: Int?) {
        self.elements = elements
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    package init(unsolvedSymbol: Symbol) {
        self.init(elements: [.string(unsolvedSymbol.stringValue)], startOffset: unsolvedSymbol.offset, endOffset: nil)
    }

    package var lookupElements: [Element.Lookup] {
        elements.compactMap { if case .lookup(let lookup) = $0 { lookup } else { nil } }
    }

    public func symbolStringValue() -> String {
        guard !elements.isEmpty else { return "" }
        let rawStringValue = rawStringValue()
        if rawStringValue.isStartWithManglePrefix {
            return rawStringValue
        } else {
            return rawStringValue.insertManglePrefix
        }
    }

    public func typeStringValue() -> String {
        guard !elements.isEmpty else { return "" }
        let rawStringValue = rawStringValue()
        if rawStringValue.isStartWithManglePrefix {
            return rawStringValue.stripManglePrefix
        } else {
            return rawStringValue
        }
    }
    
    public func rawStringValue() -> String {
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
        return results.joined(separator: "")
    }

    public var isEmpty: Bool {
        return elements.isEmpty
    }
}

extension MangledName: Resolvable {
    @MachOImageGenerator
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
            case .string(let string):
                innerLines.append("[String] \(string)")
            case .lookup(let lookup):
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
