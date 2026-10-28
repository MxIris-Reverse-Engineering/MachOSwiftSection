import Foundation
import MachOSwiftSection
import Semantic
@_spi(Internals) import Demangling
import SwiftDeclaration
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

// MARK: - @objc protocols declared in Swift

extension SwiftDeclarationPrinter {
    /// An `@objc` protocol declared in Swift (evolution proposal
    /// `swift-declared-objc-protocols`): `@objc protocol Name: Inherited`,
    /// `@objc(Name)` when the source renamed it for the runtime, then its
    /// requirements and its default-implementation extensions. One declared
    /// in a type (SE-0404) prints in an `extension` of that type, the only
    /// place a declaration printed on its own can name it from.
    ///
    /// A requirement spelled from its selector carries `@objc(selector)`:
    /// the importer's rules give it a Swift name, which may not be the
    /// source's, and the attribute keeps the selector it compiles to. One
    /// taken from a class implementing it says which class.
    public func printObjCProtocolDefinition(_ definition: ObjCProtocolDefinition, level: Int = 1) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await printIncludedObjCProtocolDefinition(definition, level: level)
        }
    }

    @SemanticStringBuilder
    private func printIncludedObjCProtocolDefinition(_ definition: ObjCProtocolDefinition, level: Int) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: definition.protocolName.name, kind: .protocol)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        try definition.index(in: machO)

        if let parentTypeNode = Self.parentTypeNode(of: definition) {
            try await DeclarationBlock(level: level) {
                Keyword(.extension)
                Space()
                try await typeDemangleResolver.resolve(for: parentTypeNode)
            } body: {
                try await NestedDeclaration {
                    try await objcProtocolDeclaration(definition, level: level + 1)
                }
            }
        } else {
            try await objcProtocolDeclaration(definition, level: level)
        }

        // Like a top-level Swift protocol, its extensions trail it.
        await BlockList {
            for extensionDefinition in definition.defaultImplementationExtensions {
                await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                ) {
                    try await printExtensionDefinition(extensionDefinition)
                }
            }
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    /// The type a protocol is declared in, `Type`-wrapped; `nil` for one
    /// declared at the top level of its module.
    private static func parentTypeNode(of definition: ObjCProtocolDefinition) -> Node? {
        guard let contextNode = definition.protocolName.node.materialize().first(of: .protocol)?.firstChild,
              contextNode.kind != .module
        else { return nil }
        return Node.createTransient(kind: .type, child: contextNode)
    }

    @SemanticStringBuilder
    private func objcProtocolDeclaration(_ definition: ObjCProtocolDefinition, level: Int) async throws -> SemanticString {
        let resolver = typeDemangleResolver
        try await DeclarationBlock(level: level) {
            Keyword(.atObjc)
            if definition.hasExplicitObjCName, let runtimeName = definition.objcRuntimeName {
                Standard("(\(runtimeName))")
            }
            Space()
            Keyword(.protocol)
            Space()
            objcProtocolLeafName(of: definition)
            for (offset, inheritedProtocolName) in definition.inheritedProtocolNames.offsetEnumerated() {
                Standard(offset.isStart ? ":" : ",")
                Space()
                try await resolver.resolve(for: inheritedProtocolName.node.materialize())
            }
        } body: {
            try await MemberList(level: level) {
                if definition.objcRuntimeName == nil {
                    Comment("No Objective-C protocol record pairs with this declaration: the source renamed it with @objc(Name) to a name other than its Swift name, so its requirements are not listed.")
                }
                if definition.requirements.contains(where: { $0.source == .selector }) {
                    Comment("Swift names follow the ClangImporter's rules for these selectors; the binary records no Swift names for them.")
                }
                for requirement in definition.requirements {
                    if case .conformer(let className) = requirement.source {
                        let printedClassName = try await resolver.resolve(for: className.node.materialize()).string
                        Comment("Taken from the conformer \(printedClassName).")
                    }
                    await printObjCProtocolRequirement(requirement, level: level)
                }
            }
        }
    }

    /// The protocol's own name, unqualified; a private one's with its
    /// discriminator, as a Swift protocol's header prints it.
    @SemanticStringBuilder
    private func objcProtocolLeafName(of definition: ObjCProtocolDefinition) -> SemanticString {
        let protocolNode = definition.protocolName.node.materialize().first(of: .protocol)
        if let leafNode = protocolNode?.children.dropFirst().first {
            if leafNode.kind == .privateDeclName {
                leafNode.printSemantic(using: [.showPrivateDiscriminators])
            } else {
                TypeDeclaration(kind: .protocol, leafNode.text ?? definition.protocolName.name)
            }
        } else {
            TypeDeclaration(kind: .protocol, definition.protocolName.name)
        }
    }

    @SemanticStringBuilder
    private func printObjCProtocolRequirement(_ requirement: ObjCProtocolRequirementDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: requirement.selector, kind: printingKind(of: requirement))) {
            Keyword(.atObjc)
            if requirement.hasExplicitSelector {
                Standard("(\(requirement.selector))")
            }
            Space()
            if requirement.isOptional {
                Keyword(.optional)
                Space()
            }
            let node = requirement.node.materialize()
            switch requirement.kind {
            case .method, .initializer:
                var printer = SemanticFunctionNodePrinter(isOverride: false, delegate: self)
                try await printer.printRoot(node)
            case .property:
                var printer = SemanticVariableNodePrinter(isStored: false, isOverride: false, hasSetter: requirement.isSettable, indentation: level, delegate: self)
                try await printer.printRoot(node)
            case .subscript:
                var printer = SemanticSubscriptNodePrinter(isOverride: false, hasSetter: requirement.isSettable, indentation: level, delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    private func printingKind(of requirement: ObjCProtocolRequirementDefinition) -> SwiftIndexEvents.PrintingDefinitionKind {
        switch requirement.kind {
        case .method, .initializer: .function
        case .property: .variable
        case .subscript: .subscript
        }
    }
}
