import Foundation
import MachOKit
import MachOFoundation

public struct MangledName: Sendable, Hashable {
    package enum Element: Sendable, Hashable {
        package struct Lookup: CustomStringConvertible, Sendable, Hashable {
            package enum Reference: Hashable, Sendable {
                case relative(RelativeReference)
                case absolute(AbsoluteReference)
            }

            package struct RelativeReference: CustomStringConvertible, Sendable, Hashable {
                package let kind: UInt8
                package let relativeOffset: RelativeOffset
                package var description: String {
                    """
                    Kind: \(kind) RelativeOffset: \(relativeOffset)
                    """
                }
            }

            package struct AbsoluteReference: CustomStringConvertible, Sendable, Hashable {
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
                    "[Relative] Offset: \(offset) \(relative)"
                case .absolute(let absolute):
                    "[Absolute] Offset: \(offset) \(absolute)"
                }
            }
        }

        case string(String)
        case lookup(Lookup)
    }

    package private(set) var elements: [Element] = []

    @usableFromInline
    package private(set) var startOffset: Int

    @usableFromInline
    package private(set) var endOffset: Int

    /*@inlinable*/
    package var size: Int {
        endOffset - startOffset
    }
    
    package init(elements: [Element], startOffset: Int, endOffset: Int) {
        self.elements = elements
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    package var lookupElements: [Element.Lookup] {
        elements.compactMap { if case .lookup(let lookup) = $0 { lookup } else { nil } }
    }

    public var symbolString: String {
        guard !elements.isEmpty else { return "" }
        let rawStringValue = rawString
        if rawStringValue.isSwiftSymbol {
            return rawStringValue
        } else {
            return rawStringValue.insertManglePrefix
        }
    }

    public var typeString: String {
        guard !elements.isEmpty else { return "" }
        let rawStringValue = rawString
        if rawStringValue.isSwiftSymbol {
            return rawStringValue.stripManglePrefix
        } else {
            return rawStringValue
        }
    }

    public var rawString: String {
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

    package func isContentsEqual(to otherMangledName: MangledName) -> Bool {
        elements == otherMangledName.elements
    }
}

extension MangledName: Resolvable {
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self {
        try resolve(from: offset, for: machO)
    }

    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        var mangledName = try resolve(from: 0, for: ptr)
        mangledName.startOffset = ptr.bitPattern.int
        mangledName.endOffset = ptr.bitPattern.int + mangledName.endOffset
        mangledName.elements = mangledName.elements.map { element in
            switch element {
            case .string:
                return element
            case .lookup(let lookup):
                return .lookup(.init(offset: ptr.advanced(by: lookup.offset).bitPattern.int, reference: lookup.reference))
            }
        }
        return mangledName
    }

    private static func resolve<Reader: Readable>(from offset: Int, for reader: Reader) throws -> MangledName {
        var elements: [MangledName.Element] = []
        var currentOffset = offset
        var currentString = ""
        while true {
            let value: UInt8 = try reader.readElement(offset: currentOffset)
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
                let reference: Int32 = try reader.readElement(offset: currentOffset + 1)
                let offset = Int(offset + (currentOffset - offset))
                elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: value, relativeOffset: reference + 1)))))
                currentOffset.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: UInt64 = try reader.readElement(offset: currentOffset + 1)
                let offset = Int(offset + (currentOffset - offset))
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(kind: value, reference: reference)))))
                currentOffset.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentOffset.offset(of: UInt8.self)
        }

        return .init(elements: elements, startOffset: offset, endOffset: currentOffset)
    }
    
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> MangledName {
        var elements: [MangledName.Element] = []
        var currentAddress = address
        var currentString = ""
        while true {
            let value: UInt8 = try context.readElement(at: currentAddress)
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                currentAddress = context.advanceAddress(currentAddress, of: UInt8.self)
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: Int32 = try context.readElement(at: context.advanceAddress(currentAddress, by: 1))
                let offset = try context.offsetFromAddress(currentAddress)
                elements.append(.lookup(.init(offset: offset, reference: .relative(.init(kind: value, relativeOffset: reference + 1)))))
                currentAddress = context.advanceAddress(currentAddress, of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: UInt64 = try context.readElement(at: context.advanceAddress(currentAddress, by: 1))
                let offset = try context.offsetFromAddress(currentAddress)
                elements.append(.lookup(.init(offset: offset, reference: .absolute(.init(kind: value, reference: reference)))))
                currentAddress = context.advanceAddress(currentAddress, of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            currentAddress = context.advanceAddress(currentAddress, of: UInt8.self)
        }

        return .init(elements: elements, startOffset: try context.offsetFromAddress(address), endOffset: try context.offsetFromAddress(currentAddress))
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
