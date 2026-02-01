import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
import MachOKit
import Dependencies
import Utilities
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

@_spi(Support)
public final class SwiftInterfacePrinter<MachO: MachOSwiftSectionRepresentableWithCache>: Sendable {
    public let machO: MachO

    @Mutex
    public private(set) var configuration: SwiftInterfacePrintConfiguration = .init()

    @Mutex
    public private(set) var typeNameResolvers: [any TypeNameResolvable] = []

    let eventDispatcher: SwiftInterfaceEvents.Dispatcher = .init()

    @Mutex
    var typeDemangleResolver: DemangleResolver = .using(options: .default)

    public init(configuration: SwiftInterfacePrintConfiguration = .init(), eventHandlers: [SwiftInterfaceEvents.Handler] = [], in machO: MachO) {
        self.machO = machO
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)
        self.typeDemangleResolver = .using { [weak self] node in
            if let self {
                var printer = TypeNodePrinter(delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    public func updateConfiguration(_ configuration: SwiftInterfacePrintConfiguration) {
        self.configuration = configuration
    }

    public func addTypeNameResolver(_ resolver: any TypeNameResolvable) {
        typeNameResolvers.append(resolver)
    }

    public func removeAllTypeNameResolvers() {
        typeNameResolvers.removeAll()
    }

    @SemanticStringBuilder
    public func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        let dumper = typeDefinition.type.dumper(
            using: .init(
                demangleResolver: typeDemangleResolver,
                indentation: level,
                displayParentName: displayParentName,
                printFieldOffset: configuration.printFieldOffset,
                printTypeLayout: configuration.printTypeLayout,
                printEnumLayout: configuration.printEnumLayout,
                fieldOffsetTransformer: configuration.fieldOffsetTransformer,
                typeLayoutTransformer: configuration.typeLayoutTransformer
            ),
            in: machO
        )

        try await DeclarationBlock(level: level) {
            try await dumper.declaration
        } body: {
            for child in typeDefinition.typeChildren {
                try await NestedDeclaration {
                    try await printTypeDefinition(child, level: level + 1)
                }
            }

            for child in typeDefinition.protocolChildren {
                try await NestedDeclaration {
                    try await printProtocolDefinition(child, level: level + 1)
                }
            }

            try await dumper.fields

            try await printDefinition(typeDefinition, level: level)
        }
    }

    @SemanticStringBuilder
    public func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        let dumper = ProtocolDumper(
            protocolDefinition.protocol,
            using: .init(
                demangleResolver: typeDemangleResolver,
                indentation: level,
                displayParentName: displayParentName,
                printFieldOffset: configuration.printFieldOffset
            ),
            in: machO
        )

        try await DeclarationBlock(level: level) {
            try await dumper.declaration
        } body: {
            try await dumper.associatedTypes

            try await printDefinition(protocolDefinition, level: level, offsetPrefix: "protocol witness table")

            if configuration.printStrippedSymbolicItem, !protocolDefinition.strippedSymbolicRequirements.isEmpty {
                MemberList(level: level) {
                    for strippedSymbolicRequirement in protocolDefinition.strippedSymbolicRequirements {
                        strippedSymbolicRequirement.strippedSymbolicInfo()
                    }
                }
            }
        }

        if protocolDefinition.parent == nil {
            try await BlockList {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    try await printExtensionDefinition(extensionDefinition)
                }
            }
        }
    }

    @SemanticStringBuilder
    public func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition, level: Int = 1) async throws -> SemanticString {
        if !extensionDefinition.isIndexed {
            try await extensionDefinition.index(in: machO)
        }

        try await DeclarationBlock(level: level) {
            Keyword(.extension)
            Space()
            extensionDefinition.extensionName.print()

            if let protocolConformance = extensionDefinition.protocolConformance,
               let protocolName = try? await protocolConformance.dumpProtocolName(using: .demangleOptions(.interfaceTypeBuilderOnly), in: machO) {
                Standard(":")
                Space()
                protocolName
            }

            if let genericSignature = extensionDefinition.genericSignature {
                let nodes = genericSignature.all(of: .requirementKinds)
                for (index, node) in nodes.enumerated() {
                    if index == 0 {
                        Space()
                        Keyword(.where)
                        Space()
                    }

                    try await printThrowingType(node, isProtocol: extensionDefinition.extensionName.isProtocol, level: level)

                    if index < nodes.count - 1 {
                        Standard(",")
                        Space()
                    }
                }
            }
        } body: {
            for typeDefinition in extensionDefinition.types {
                try await NestedDeclaration {
                    try await printTypeDefinition(typeDefinition, level: level + 1)
                }
            }

            for protocolDefinition in extensionDefinition.protocols {
                try await NestedDeclaration {
                    try await printProtocolDefinition(protocolDefinition, level: level + 1)
                }
            }

            if let associatedType = extensionDefinition.associatedType {
                let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleResolver: typeDemangleResolver), in: machO)
                try await dumper.records
            }

            try await printDefinition(extensionDefinition, level: 1)
        }
    }

    @SemanticStringBuilder
    public func printDefinition(_ definition: some Definition, level: Int = 1, offsetPrefix: String = "") async throws -> SemanticString {
        if let mutableDefinition = definition as? MutableDefinition, !mutableDefinition.isIndexed {
            try await mutableDefinition.index(in: machO)
        }

        let printFieldOffset = configuration.printFieldOffset

        await MemberList(level: level) {
            for allocator in definition.allocators {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: allocator.offset, emit: printFieldOffset)
                await printFunction(allocator)
            }
        }

        await MemberList(level: level) {
            for variable in definition.variables {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: variable.offset, emit: printFieldOffset)
                await printVariable(variable, level: level)
            }
        }

        await MemberList(level: level) {
            for function in definition.functions {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: function.offset, emit: printFieldOffset)
                await printFunction(function)
            }
        }

        await MemberList(level: level) {
            for `subscript` in definition.subscripts {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: `subscript`.offset, emit: printFieldOffset)
                await printSubscript(`subscript`, level: level)
            }
        }

        await MemberList(level: level) {
            for variable in definition.staticVariables {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: variable.offset, emit: printFieldOffset)
                await printVariable(variable, level: level)
            }
        }

        await MemberList(level: level) {
            for function in definition.staticFunctions {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: function.offset, emit: printFieldOffset)
                await printFunction(function)
            }
        }

        await MemberList(level: level) {
            for `subscript` in definition.staticSubscripts {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: `subscript`.offset, emit: printFieldOffset)
                await printSubscript(`subscript`, level: level)
            }
        }
    }

    @SemanticStringBuilder
    public func printVariable(_ variable: VariableDefinition, level: Int) async -> SemanticString {
        await printCatchedThrowing {
            try await printThrowingVariable(variable, level: level)
        }
    }

    @SemanticStringBuilder
    public func printFunction(_ function: FunctionDefinition) async -> SemanticString {
        await printCatchedThrowing {
            try await printThrowingFunction(function)
        }
    }

    @SemanticStringBuilder
    public func printSubscript(_ `subscript`: SubscriptDefinition, level: Int) async -> SemanticString {
        await printCatchedThrowing {
            try await printThrowingSubscript(`subscript`, level: level)
        }
    }

    @SemanticStringBuilder
    public func printType(_ typeNode: Node, isProtocol: Bool, level: Int) async -> SemanticString {
        await printCatchedThrowing {
            try await printThrowingType(typeNode, isProtocol: isProtocol, level: level)
        }
    }

    @SemanticStringBuilder
    public func printThrowingVariable(_ variable: VariableDefinition, level: Int) async throws -> SemanticString {
        var printer = VariableNodePrinter(isStored: variable.isStored, isOverride: variable.isOverride, hasSetter: variable.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(variable.node)
    }

    @SemanticStringBuilder
    public func printThrowingFunction(_ function: FunctionDefinition) async throws -> SemanticString {
        var printer = FunctionNodePrinter(isOverride: function.isOverride, delegate: self)
        try await printer.printRoot(function.node)
    }

    @SemanticStringBuilder
    public func printThrowingSubscript(_ `subscript`: SubscriptDefinition, level: Int) async throws -> SemanticString {
        var printer = SubscriptNodePrinter(isOverride: `subscript`.isOverride, hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(`subscript`.node)
    }

    @SemanticStringBuilder
    public func printThrowingType(_ typeNode: Node, isProtocol: Bool, level: Int) async throws -> SemanticString {
        var printer = TypeNodePrinter(delegate: self, isProtocol: isProtocol)
        try await printer.printRoot(typeNode)
    }
}

func printCatchedThrowing(@SemanticStringBuilder _ body: () async throws -> SemanticString) async -> SemanticString? {
    do {
        return try await body()
    } catch {
        print(error)
        return nil
    }
}

extension SwiftInterfacePrinter: NodePrintableDelegate {
    public func moduleName(forTypeName typeName: String) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.moduleName(forTypeName: typeName) }
    }

    public func swiftName(forCName cName: String) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.swiftName(forCName: cName) }
    }

    public func opaqueType(forNode node: Node, index: Int?) async -> String? {
        await typeNameResolvers.asyncFirstNonNil { await $0.opaqueType(forNode: node, index: index) }
    }
}
