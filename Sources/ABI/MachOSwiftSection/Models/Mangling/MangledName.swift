import Foundation
import MachOKit
import MachOBase

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
        if rawStringValue.hasSwiftManglingPrefix {
            return rawStringValue
        } else {
            return rawStringValue.insertManglePrefix
        }
    }

    public var typeString: String {
        guard !elements.isEmpty else { return "" }
        let rawStringValue = rawString
        if rawStringValue.hasSwiftManglingPrefix {
            return rawStringValue.strippingSwiftManglingPrefix
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
    /// Parses the mangled name that starts at `address`.
    ///
    /// Every offset in the result — the start, the end and each lookup
    /// element's — is `offsetFromAddress(address)` plus a distance from the
    /// start: a file offset in a `MachOContext`, an absolute pointer bit
    /// pattern in `InProcessContext`, which `RuntimeFunctions` hands to the
    /// runtime as the name's start. A context that strips tag bits when it
    /// reads therefore never mixes a tagged start with untagged offsets.
    public static func resolve<Context: ReadingContext>(at address: Context.Address, in context: Context) throws -> MangledName {
        let startOffset = try context.offsetFromAddress(address)
        var elements: [MangledName.Element] = []
        var distanceFromStart = 0
        var currentString = ""
        while true {
            let currentAddress = context.advanceAddress(address, by: distanceFromStart)
            let value: UInt8 = try context.readElement(at: currentAddress)
            if value == 0xFF {}
            else if value == 0 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                distanceFromStart.offset(of: UInt8.self)
                break
            } else if value >= 0x01, value <= 0x17 {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: Int32 = try context.readElement(at: context.advanceAddress(currentAddress, by: 1))
                elements.append(.lookup(.init(offset: startOffset + distanceFromStart, reference: .relative(.init(kind: value, relativeOffset: reference + 1)))))
                distanceFromStart.offset(of: Int32.self)
            } else if value >= 0x18, value <= 0x1F {
                if currentString.count > 0 {
                    elements.append(.string(currentString))
                    currentString = ""
                }
                let reference: UInt64 = try context.readElement(at: context.advanceAddress(currentAddress, by: 1))
                elements.append(.lookup(.init(offset: startOffset + distanceFromStart, reference: .absolute(.init(kind: value, reference: reference)))))
                distanceFromStart.offset(of: UInt64.self)
            } else {
                currentString.append(String(format: "%c", value))
            }
            distanceFromStart.offset(of: UInt8.self)
        }

        return .init(elements: elements, startOffset: startOffset, endOffset: startOffset + distanceFromStart)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MangledName {
    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: offset, in: machO.context).")
    public static func resolve(from offset: Int, in machO: some MachORepresentableWithCache & Readable) throws -> Self {
        try resolve(at: offset, in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: resolve(at: pointer, in: .inProcess).")
    public static func resolve(from ptr: UnsafeRawPointer) throws -> Self {
        try resolve(at: ptr, in: InProcessContext.shared)
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
