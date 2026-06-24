import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Utilities
import Demangling
import OrderedCollections
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

package struct ProtocolDumper<MachO: FieldLayoutRenderable>: NamedDumper {
    package let dumped: MachOSwiftSection.`Protocol`

    package let configuration: DumperConfiguration

    package let machO: MachO

    package init(_ dumped: MachOSwiftSection.`Protocol`, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.protocol)

            Space()

            try await name

            if dumped.numberOfRequirementsInSignature > 0 {
                var requirementInSignatures = dumped.requirementInSignatures
                for (offset, requirement) in requirementInSignatures.extract(where: \.isProtocolInherited).offsetEnumerated() {
                    if offset.isStart {
                        Standard(":")
                    } else {
                        Standard(",")
                    }
                    Space()
                    try await requirement.descriptor.dumpContent(resolver: demangleResolver, in: machO)
                }
                if !requirementInSignatures.isEmpty {
                    Space()
                    Keyword(.where)
                    Space()

                    for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                        try await requirement.descriptor.dumpProtocolRequirement(resolver: demangleResolver, in: machO)
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
        get async throws {
            let associatedTypes = try dumped.descriptor.associatedTypes(in: machO)

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
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await associatedTypes

            var defaultImplementations: OrderedSet<Node> = []

            for (offset, requirement) in dumped.requirements.offsetEnumerated() {
                BreakLine()
                Indent(level: configuration.indentation)
                if let symbols = try await Symbols.resolve(from: requirement.offset, in: machO), let validNode = try await validNode(for: symbols) {
                    try await demangleResolver.resolve(for: validNode)
                } else {
                    InlineComment("[Stripped Symbol]")
                }

                if let symbols = try requirement.defaultImplementationSymbols(in: machO), let defaultImplementation = try await validNode(for: symbols, visitedNode: defaultImplementations) {
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
                try await demangleResolver.resolve(for: defaultImplementation)

                if offset.isEnd {
                    BreakLine()
                }
            }
            Standard("}")
        }
    }

    package var name: SemanticString {
        get async throws {
            try await _name(using: demangleResolver)
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .protocol(dumped.descriptor), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .protocol, dumped.descriptor.name(in: machO))
        }
    }

    private func validNode(for symbols: Symbols, visitedNode: borrowing OrderedSet<Node> = []) async throws -> Node? {
        let currentInterfaceName = try await _name(using: .options(.interfaceType)).string
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), await protocolNode.print(using: .interfaceType) == currentInterfaceName, !visitedNode.contains(node) {
                return node
            }
        }
        return nil
    }
}

