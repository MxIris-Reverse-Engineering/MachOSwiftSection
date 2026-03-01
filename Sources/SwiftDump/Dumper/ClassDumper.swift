import Semantic
import Demangling
import MachOKit
import MachOSwiftSection
import Utilities
import Dependencies
import OrderedCollections
@_spi(Internals) import MachOSymbols
import SwiftInspection

package struct ClassDumper<MachO: MachOSwiftSectionRepresentableWithCache>: TypedDumper {
    package typealias Dumped = Class

    package typealias Metadata = ClassMetadataObjCInterop

    package let dumped: Dumped

    package let metadata: Metadata?

    package let configuration: DumperConfiguration

    package let machO: MachO

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    package init(_ dumped: Dumped, using configuration: DumperConfiguration, in machO: MachO) {
        self.init(dumped, metadata: nil, using: configuration, in: machO)
    }

    package init(_ dumped: Dumped, metadata: Metadata?, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.metadata = metadata
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            if dumped.descriptor.isActor {
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            try await name
            let superclass = try await superclass
            if let genericContext = dumped.genericContext {
                try await genericContext.dumpGenericSignature(resolver: demangleResolver, in: machO) {
                    superclass
                }
            } else {
                superclass
            }
        }
    }

    @SemanticStringBuilder
    package var superclass: SemanticString {
        get async throws {
            if let superclassMangledName = try dumped.descriptor.superclassTypeMangledName(in: machO) {
                Standard(":")
                Space()
                try await demangleResolver.resolve(for: MetadataReader.demangleType(for: superclassMangledName, in: machO))
            } else if let resilientSuperclass = dumped.resilientSuperclass, let kind = dumped.descriptor.resilientSuperclassReferenceKind, let superclass = try await resilientSuperclass.dumpSuperclass(resolver: demangleResolver, for: kind, in: machO) {
                Standard(":")
                Space()
                superclass
            }
        }
    }

    private var fieldOffsets: [Int]? {
        guard configuration.printFieldOffset else { return nil }
        guard let metadataAccessor = try? dumped.descriptor.metadataAccessorFunction(in: machO), !dumped.flags.isGeneric else { return nil }
        guard let metadataWrapper = try? metadataAccessor(request: .init()).value.resolve(in: machO) else { return nil }
        switch metadataWrapper {
        case .class(let metadata):
            return try? metadata.fieldOffsets(for: dumped.descriptor, in: machO).map { $0.cast() }
        default:
            return nil
        }
    }

    package var fields: SemanticString {
        get async throws {
            let fieldOffsets = fieldOffsets
            for (offset, fieldRecord) in try dumped.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                BreakLine()

                let mangledTypeName = try fieldRecord.mangledTypeName(in: machO)

                if let fieldOffsets, let startOffset = fieldOffsets[safe: offset.index] {
                    let endOffset: Int?
                    if let nextFieldOffset = fieldOffsets[safe: offset.index + 1] {
                        endOffset = nextFieldOffset
                    } else if !dumped.flags.isGeneric,
                              let machOImage = machO.asMachOImage,
                              let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machOImage),
                              let metadata = try? Metadata.createInProcess(metatype),
                              let typeLayout = try? metadata.asMetadataWrapper().valueWitnessTable().typeLayout {
                        endOffset = startOffset + Int(typeLayout.size)
                    } else {
                        endOffset = nil
                    }
                    configuration.fieldOffsetComment(startOffset: startOffset, endOffset: endOffset)
                }

                if configuration.printTypeLayout, !dumped.flags.isGeneric, let machO = machO.asMachOImage, let metatype = try? RuntimeFunctions.getTypeByMangledNameInContext(mangledTypeName, in: machO), let metadata = try? Metadata.createInProcess(metatype) {
                    try await metadata.asMetadataWrapper().dumpTypeLayout(using: configuration)
                }

                Indent(level: configuration.indentation)

                let demangledTypeNode = try MetadataReader.demangleType(for: mangledTypeName, in: machO)

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

                try await demangleResolver.modify {
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
        get async throws {
            try await declaration

            Space()

            Standard("{")

            try await fields

            var methodVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in dumped.methodDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                dumpMethodKind(for: descriptor)

                dumpMethodKeyword(for: descriptor)

                try await dumpMethodDeclaration(for: descriptor, visitedNodes: &methodVisitedNodes)

                if offset.isEnd {
                    BreakLine()
                }
            }

            var methodOverrideVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in dumped.methodOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                let methodDescriptor = try descriptor.methodDescriptor(in: machO)

                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try await validNode(for: symbols, visitedNodes: methodOverrideVisitedNodes) {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    try await demangleResolver.resolve(for: node)
                    _ = methodOverrideVisitedNodes.append(node)
                } else if !descriptor.implementation.isNull {
                    dumpMethodKind(for: methodDescriptor?.resolved)
                    Keyword(.override)
                    Space()
                    FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
                } else if let methodDescriptor {
                    switch methodDescriptor {
                    case .symbol(let symbol):
                        Keyword(.override)
                        Space()
                        try await MetadataReader.demangleSymbol(for: symbol, in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
                    case .element(let element):
                        dumpMethodKind(for: element)
                        Keyword(.override)
                        Space()
                        dumpMethodKeyword(for: element)
                        try? await dumpMethodDeclaration(for: element, visitedNodes: &methodOverrideVisitedNodes)
                    }
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            var methodDefaultOverrideVisitedNodes: OrderedSet<Node> = []
            for (offset, descriptor) in dumped.methodDefaultOverrideDescriptors.offsetEnumerated() {
                BreakLine()

                if configuration.printMemberAddress, !descriptor.implementation.isNull {
                    let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                    configuration.memberAddressComment(offset: implOffset, addressString: machO.addressString(forOffset: implOffset))
                }

                Indent(level: 1)

                Keyword(.override)

                Space()

                if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try await validNode(for: symbols, visitedNodes: methodDefaultOverrideVisitedNodes) {
                    try await demangleResolver.resolve(for: node)
                    _ = methodDefaultOverrideVisitedNodes.append(node)
                } else if !descriptor.implementation.isNull {
                    FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
                } else {
                    Error("Symbol not found")
                }

                if offset.isEnd {
                    BreakLine()
                }
            }

            let interfaceNameString = try await interfaceName.string

            for kind in SymbolIndexStore.MemberKind.allCases {
                for (offset, symbol) in symbolIndexStore.memberSymbols(of: kind, for: interfaceNameString, in: machO).offsetEnumerated() {
                    if offset.isStart {
                        BreakLine()

                        Indent(level: 1)

                        InlineComment(kind.description)
                    }

                    BreakLine()

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }

                    Indent(level: 1)

                    try await demangleResolver.resolve(for: symbol.demangledNode)

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

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: symbol.offset, addressString: machO.addressString(forOffset: symbol.offset))
                    }

                    Indent(level: 1)

                    try await demangleResolver.resolve(for: symbol.demangledNode)

                    if offset.isEnd {
                        BreakLine()
                    }
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

    private var interfaceName: SemanticString {
        get async throws {
            try await _name(using: .options(.interface))
        }
    }

    @SemanticStringBuilder
    private func _name(using resolver: DemangleResolver) async throws -> SemanticString {
        if configuration.displayParentName {
            try await resolver.resolve(for: MetadataReader.demangleContext(for: .type(.class(dumped.descriptor)), in: machO)).replacingTypeNameOrOtherToTypeDeclaration()
        } else {
            try TypeDeclaration(kind: .class, dumped.descriptor.name(in: machO))
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
    private func dumpMethodDeclaration(for descriptor: MethodDescriptor, visitedNodes: inout OrderedSet<Node>) async throws -> SemanticString {
        if let symbols = try? descriptor.implementationSymbols(in: machO), let node = try await validNode(for: symbols, visitedNodes: visitedNodes) {
            try await demangleResolver.resolve(for: node)
            _ = visitedNodes.append(node)
        } else if !descriptor.implementation.isNull {
            FunctionDeclaration(machO.addressString(forOffset: descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))).insertSubFunctionPrefix)
        } else {
            Error("Symbol not found")
        }
    }

    package func validNode(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) async throws -> Node? {
        let currentInterfaceName = try await _name(using: .options(.interfaceType)).string
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
