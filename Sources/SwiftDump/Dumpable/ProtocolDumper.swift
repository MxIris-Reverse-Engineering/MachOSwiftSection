import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Demangle
import OrderedCollections

package struct ProtocolDumper<MachO: MachOSwiftSectionRepresentableWithCache>: NamedDumper {
    let `protocol`: MachOSwiftSection.`Protocol`

    let options: DemangleOptions

    let machO: MachO

    package var body: SemanticString {
        get throws {
            Keyword(.protocol)

            Space()

            try name

            if `protocol`.numberOfRequirementsInSignature > 0 {
                Space()
                Keyword(.where)
                Space()

                for (offset, requirement) in `protocol`.requirementInSignatures.offsetEnumerated() {
                    try requirement.dump(using: options, in: machO)
                    if !offset.isEnd {
                        Standard(",")
                        Space()
                    }
                }
            }
            Space()
            Standard("{")

            let associatedTypes = try `protocol`.descriptor.associatedTypes(in: machO)

            if !associatedTypes.isEmpty {
                for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                    BreakLine()
                    Indent(level: 1)
                    Keyword(.associatedtype)
                    Space()
                    TypeDeclaration(kind: .other, associatedType)
                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            var defaultImplementations: OrderedSet<Node> = []

            for (offset, requirement) in `protocol`.requirements.offsetEnumerated() {
                BreakLine()
                Indent(level: 1)
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
                    Indent(level: 1)
                    InlineComment("[Default Implementation]")
                }

                BreakLine()
                Indent(level: 1)
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
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.preorder().first(where: { $0.kind == .protocol }), protocolNode.print(using: .interfaceType) == currentInterfaceName, !visitedNode.contains(node) {
                return node
            }
        }
        return nil
    }
}
