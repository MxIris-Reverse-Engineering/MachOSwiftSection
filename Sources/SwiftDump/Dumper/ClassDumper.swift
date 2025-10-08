import Semantic
import Demangle
import MachOKit
import MachOSwiftSection
import Utilities
import Dependencies
import OrderedCollections
@_spi(Internal) import MachOSymbols

package struct ClassDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    private let `class`: Class

    private let configuration: DumperConfiguration

    private let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore
    
    package init(_ dumped: Class, using configuration: DumperConfiguration, in machO: MachO) {
        self.class = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get throws {
            if `class`.descriptor.isActor {
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            try name

            if let genericContext = `class`.genericContext {
                try genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO) {
                    try superclass
                }
            } else {
                try superclass
            }
        }
    }

    @SemanticStringBuilder
    package var superclass: SemanticString {
        get throws {
            if let superclassMangledName = try `class`.descriptor.superclassTypeMangledName(in: machO) {
                Standard(":")
                Space()
                try demangleResolver.resolve(for: MetadataReader.demangleType(for: superclassMangledName, in: machO))
            } else if let resilientSuperclass = `class`.resilientSuperclass, let kind = `class`.descriptor.resilientSuperclassReferenceKind, let superclass = try resilientSuperclass.dumpSuperclass(resolver: demangleResolver, for: kind, in: machO) {
                Standard(":")
                Space()
                superclass
            }
        }
    }
    
    
    package var fields: SemanticString {
        get throws {
            for (offset, fieldRecord) in try `class`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                Indent(level: configuration.indentation)

                let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

                let fieldName = try fieldRecord.fieldName(in: machO)

                if fieldRecord.flags.contains(.isVariadic) {
                    if demangledTypeNode.contains(.weak) {
                        Keyword(.weak)
                        Space()
                        Keyword(.var)
                        Space()
                    } else if fieldName.hasLazyPrefix {
                        Keyword(.lazy)
                        Space()
                        Keyword(.var)
                        Space()
                    } else {
                        Keyword(.var)
                        Space()
                    }
                } else {
                    Keyword(.let)
                    Space()
                }

                MemberDeclaration(fieldName.stripLazyPrefix)

                Standard(":")

                Space()

                try demangleResolver.modify {
                    if case .options(let demangleOptions) = $0 {
                        return .options(demangleOptions.union(.removeWeakPrefix))
                    } else {
                        return $0
                    }
                }
                .resolve(for: demangledTypeNode)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration

            Space()

            Standard("{")

            try fields

            var methodVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in `class`.methodDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                dumpMethodKind(for: descriptor)

                dumpMethodKeyword(for: descriptor)

                try dumpMethodDeclaration(for: descriptor, visitedNodes: &methodVisitedNodes)

                if offset.isEnd {
                    BreakLine()
                }
            }

            var methodOverrideVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in `class`.methodOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)
                
                let methodDescriptor = try descriptor.methodDescriptor(in: machO)
                
                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try validNode(for: symbols, visitedNodes: methodOverrideVisitedNodes) {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    try demangleResolver.resolve(for: node)
                    _ = methodOverrideVisitedNodes.append(node)
                } else if !descriptor.implementation.isNull {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                } else if let methodDescriptor {
                    switch methodDescriptor {
                    case .symbol(let symbol):
                        Keyword(.override)
                        Space()
                        try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
                    case .element(let element):
                        dumpMethodKind(for: element)
                        Keyword(.override)
                        Space()
                        dumpMethodKeyword(for: element)
                        try? dumpMethodDeclaration(for: element, visitedNodes: &methodOverrideVisitedNodes)
                    }
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            var methodDefaultOverrideVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in `class`.methodDefaultOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                Indent(level: 1)

                Keyword(.override)

                Space()

                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try validNode(for: symbols, visitedNodes: methodDefaultOverrideVisitedNodes) {
                    try demangleResolver.resolve(for: node)
                    _ = methodDefaultOverrideVisitedNodes.append(node)
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            let interfaceNameString = try interfaceName.string

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.methodDescriptorMemberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment("[Method] " + kind.description)
                    }

                    BreakLine()

                    Indent(level: 1)

                    try demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
                }
            }

            Standard("}")
        }
    }

    package var name: SemanticString {
        get throws {
            try _name(using: demangleResolver)
        }
    }

    private var interfaceName: SemanticString {
        get throws {
            try _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) throws -> SemanticString {
        if configuration.displayParentName {
            try resolver.resolve(for: MetadataReader.demangleContext(for: .type(.class(`class`.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .class, `class`.descriptor.name(in: machO))
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKind(for descriptor: MethodDescriptor?) -> SemanticString? {
        if let descriptor {
            InlineComment("[\(descriptor.flags.kind)]")

            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodKeyword(for descriptor: MethodDescriptor) -> SemanticString {
        if !descriptor.flags.isInstance, descriptor.flags.kind != .`init` {
            Keyword(.static)
            Space()
        }

        if descriptor.flags.isDynamic {
            Keyword(.dynamic)
            Space()
        }

        if descriptor.flags.kind == .method {
            Keyword(.func)
            Space()
        }
    }

    @SemanticStringBuilder
    private func dumpMethodDeclaration(for descriptor: MethodDescriptor, visitedNodes: inout OrderedSet<Node>) throws -> SemanticString {
        if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try validNode(for: symbols, visitedNodes: visitedNodes) {
            try demangleResolver.resolve(for: node)
            _ = visitedNodes.append(node)
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(addressString(of: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }
    
    package func validNode(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
        let currentInterfaceName = try _name(using: .options(.interfaceType)).string
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let classNode = node.first(of: .class), classNode.print(using: .interfaceType) == currentInterfaceName, !visitedNodes.contains(node) {
                return node
            }
        }
        return nil
    }
}

package func classDemangledSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(for symbols: Symbols, typeNode: Node, visitedNodes: borrowing OrderedSet<Node> = [], in machO: MachO) throws -> DemangledSymbol? {
    for symbol in symbols {
        if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let classNode = node.first(of: .class), classNode == typeNode.first(of: .class), !visitedNodes.contains(node) {
            return .init(symbol: symbol, demangledNode: node)
        }
    }
    return nil
}
