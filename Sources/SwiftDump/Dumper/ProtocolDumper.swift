import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Demangle
import OrderedCollections

package struct ProtocolDumper<MachO: MachOSwiftSectionRepresentableWithCache>: NamedDumper {
    private let `protocol`: MachOSwiftSection.`Protocol`

    private let configuration: DumperConfiguration

    private let machO: MachO

    package init(_ dumped: MachOSwiftSection.`Protocol`, using configuration: DumperConfiguration, in machO: MachO) {
        self.protocol = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var options: DemangleOptions {
        configuration.demangleOptions
    }

    package var declaration: SemanticString {
        get throws {
            Keyword(.protocol)

            Space()

            try name

            if `protocol`.numberOfRequirementsInSignature > 0 {
                var requirementInSignatures = `protocol`.requirementInSignatures
                for (offset, requirement) in requirementInSignatures.extract(where: \.isProtocolInherited).offsetEnumerated() {
                    if offset.isStart {
                        Standard(":")
                    } else {
                        Standard(",")
                    }
                    Space()
                    try requirement.descriptor.dumpContent(using: options, in: machO)
                }
                if !requirementInSignatures.isEmpty {
                    Space()
                    Keyword(.where)
                    Space()

                    for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                        try requirement.descriptor.dumpProtocolRequirement(using: options, in: machO)
                        if !offset.isEnd {
                            Standard(",")
                            Space()
                        }
                    }
                }
            }
        }
    }
    
    @SemanticStringBuilder
    package var associatedTypes: SemanticString {
        get throws {
            let associatedTypes = try `protocol`.descriptor.associatedTypes(in: machO)

            if !associatedTypes.isEmpty {
                for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                    BreakLine()
                    Indent(level: configuration.indentation)
                    Keyword(.associatedtype)
                    Space()
                    TypeDeclaration(kind: .other, associatedType)
                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }
        }
    }
    

    package var body: SemanticString {
        get throws {
            try declaration

            Space()

            Standard("{")

            try associatedTypes

            var defaultImplementations: OrderedSet<Node> = []

            for (offset, requirement) in `protocol`.requirements.offsetEnumerated() {
                BreakLine()
                Indent(level: configuration.indentation)
                if let symbols = try Symbols.resolve(from: requirement.offset, in: machO), let validNode = try validNode(for: symbols) {
                    validNode.printSemantic(using: options)
                } else {
                    InlineComment("[Stripped Symbol]")
                }

                if let symbols = try requirement.defaultImplementationSymbols(in: machO), let defaultImplementation = try validNode(for: symbols, visitedNode: defaultImplementations) {
                    _ = defaultImplementations.append(defaultImplementation)
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            for (offset, defaultImplementation) in defaultImplementations.offsetEnumerated() {
                if offset.isStart {
                    BreakLine()
                    Indent(level: configuration.indentation)
                    InlineComment("[Default Implementation]")
                }

                BreakLine()
                Indent(level: configuration.indentation)
                defaultImplementation.printSemantic(using: options)

                if offset.isEnd {
                    BreakLine()
                }
            }
            Standard("}")
        }
    }

    package var name: SemanticString {
        get throws {
            try _name(using: options)
        }
    }

    private func _name(using options: DemangleOptions) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .protocol(`protocol`.descriptor), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    private func validNode(for symbols: Symbols, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        let currentInterfaceName = try _name(using: .interfaceType).string
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceType) == currentInterfaceName, !visitedNode.contains(node) {
                return node
            }
        }
        return nil
    }
}


extension GenericRequirement {
    var isProtocolInherited: Bool {
        paramManagledName.rawString == "x" && (flags.kind == .protocol || flags.kind == .layout || flags.kind == .baseClass)
    }
}

extension RangeReplaceableCollection {
    
    /**
     * Removes and returns the elements that satisfy the given predicate.
     * This method performs the filtering and removal in a single pass.
     *
     * - Parameter predicate: A closure that takes an element of the
     *   sequence as its argument and returns a Boolean value indicating
     *   whether the element should be extracted.
     * - Returns: An array containing the elements that were removed from the collection.
     * - Complexity: O(n), where n is the length of the collection.
     */
    @discardableResult
    mutating func extract(
        where predicate: (Element) throws -> Bool
    ) rethrows -> [Element] {
        
        // Create a new collection to store the elements that will remain.
        // We can't modify the collection while iterating over it directly,
        // so we build a new one for the elements to keep.
        var remainingElements = Self()
        
        // Create an array to store the elements that are extracted.
        var extractedElements: [Element] = []
        
        // Iterate through each element of the original collection.
        for element in self {
            // Check if the element satisfies the predicate.
            if try predicate(element) {
                // If it matches, add it to the extracted list.
                extractedElements.append(element)
            } else {
                // If it doesn't match, add it to the list of elements to keep.
                remainingElements.append(element)
            }
        }
        
        // Replace the original collection's content with the remaining elements.
        self = remainingElements
        
        // Return the array of extracted elements.
        return extractedElements
    }
}

