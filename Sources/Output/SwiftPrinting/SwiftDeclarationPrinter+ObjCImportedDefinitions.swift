import Foundation
import MachOSwiftSection
import Semantic
@_spi(Internals) import Demangling
import SwiftDeclaration
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

// MARK: - Objective-C declarations as Swift imports them

extension SwiftDeclarationPrinter {
    /// An Objective-C class as Swift imports it (evolution proposal
    /// `objc-imported-declarations`): `class Name: Superclass, Protocol…`
    /// and its members, named by the importer's rules.
    ///
    /// A Swift class prints as the Swift class it is, followed by an
    /// `extension` of the Objective-C methods no member of it answers to. An
    /// `@objc @implementation` class prints each member the implementing
    /// extension answers to as that Swift member, and the rest by the rules.
    public func printObjCImportedClassDefinition(_ definition: ObjCImportedClassDefinition, level: Int = 1) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await printIncludedObjCImportedClassDefinition(definition, level: level)
        }
    }

    /// An Objective-C category as Swift imports it: `extension Class:
    /// Protocol…` and its members. A category Swift wrote prints each member
    /// as the Swift member answering to it.
    public func printObjCImportedCategoryDefinition(_ definition: ObjCImportedCategoryDefinition, level: Int = 1) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await printIncludedObjCImportedCategoryDefinition(definition, level: level)
        }
    }

    /// An Objective-C protocol as Swift imports it: `protocol Name:
    /// Inherited…`, its requirements named by the importer's rules, the
    /// optional ones marked `optional`.
    public func printObjCImportedProtocolDefinition(_ definition: ObjCImportedProtocolDefinition, level: Int = 1) async throws -> SemanticString {
        try await LargeStackTaskExecution.run {
            try await printIncludedObjCImportedProtocolDefinition(definition, level: level)
        }
    }

    // MARK: Classes

    @SemanticStringBuilder
    private func printIncludedObjCImportedClassDefinition(_ definition: ObjCImportedClassDefinition, level: Int) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: definition.className.name, kind: .type)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        try definition.index(in: machO)

        if let swiftClassDefinition = definition.swiftClassDefinition {
            try await printTypeDefinition(swiftClassDefinition, level: level)
            let swiftMembers = try implementingSwiftMembers(typeDefinitions: [swiftClassDefinition], extensionDefinitions: swiftClassDefinition.extensions)
            let unimplementedMembers = definition.members.filter { swiftMembers.member(answering: $0) == nil }
            if !unimplementedMembers.isEmpty {
                try await DeclarationBlock(level: level) {
                    Keyword(.extension)
                    Space()
                    renderExtendedTypeName(definition.className.extensionName)
                } body: {
                    try await MemberList(level: level) {
                        comment(.note("Objective-C methods of the class that no member of the Swift class answers to. Swift names follow the ClangImporter's rules for these selectors."), as: .note)
                        for member in unimplementedMembers {
                            await printObjCImportedMember(member, level: level)
                        }
                    }
                }
            }
        } else {
            let swiftMembers = try implementingSwiftMembers(typeDefinitions: [], extensionDefinitions: definition.implementationExtensions)
            let inheritedNodes = [definition.superclassName?.node].compactMap { $0 } + definition.protocolNames.map(\.node)
            try await DeclarationBlock(level: level) {
                Keyword(.class)
                Space()
                TypeDeclaration(kind: .class, Self.leafName(of: definition.className.node, kind: .class) ?? definition.objcRuntimeName)
                try await inheritanceClause(inheritedNodes)
            } body: {
                try await objcImportedMemberList(definition.members, swiftMembers: swiftMembers, level: level)
            }
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    // MARK: Categories

    @SemanticStringBuilder
    private func printIncludedObjCImportedCategoryDefinition(_ definition: ObjCImportedCategoryDefinition, level: Int) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: definition.uniqueName, kind: .extension)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        try definition.index(in: machO)
        let swiftMembers = try implementingSwiftMembers(typeDefinitions: [], extensionDefinitions: definition.swiftExtensions)

        try await DeclarationBlock(level: level) {
            Keyword(.extension)
            Space()
            renderExtendedTypeName(definition.extendedClassName.extensionName)
            try await inheritanceClause(definition.protocolNames.map(\.node))
        } body: {
            try await objcImportedMemberList(definition.members, swiftMembers: swiftMembers, leadingNote: "The Objective-C category \(definition.uniqueName).", level: level)
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    // MARK: Protocols

    @SemanticStringBuilder
    private func printIncludedObjCImportedProtocolDefinition(_ definition: ObjCImportedProtocolDefinition, level: Int) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: definition.protocolName.name, kind: .protocol)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        try definition.index(in: machO)

        try await DeclarationBlock(level: level) {
            Keyword(.protocol)
            Space()
            TypeDeclaration(kind: .protocol, Self.leafName(of: definition.protocolName.node, kind: .protocol) ?? definition.objcRuntimeName)
            try await inheritanceClause(definition.inheritedProtocolNames.map(\.node))
        } body: {
            try await MemberList(level: level) {
                if !definition.requirements.isEmpty {
                    comment(.note("Swift names follow the ClangImporter's rules for these selectors; the binary records no Swift names for them."), as: .note)
                }
                for requirement in definition.requirements {
                    await printObjCImportedRequirement(requirement, level: level)
                }
            }
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    // MARK: Members

    @SemanticStringBuilder
    private func objcImportedMemberList(_ members: [ObjCImportedMemberDefinition], swiftMembers: ObjCImplementingSwiftMembers, leadingNote: String? = nil, level: Int) async throws -> SemanticString {
        try await MemberList(level: level) {
            if let leadingNote {
                comment(.note(leadingNote), as: .note)
            }
            if members.contains(where: { swiftMembers.member(answering: $0) == nil }) {
                comment(.note("Swift names follow the ClangImporter's rules for these selectors; the binary records no Swift names for them."), as: .note)
            }
            for member in members {
                if let swiftMember = swiftMembers.member(answering: member) {
                    switch swiftMember {
                    case .function(let function):
                        await printFunction(function, level: level)
                    case .variable(let variable):
                        await printVariable(variable, level: level)
                    case .subscript(let `subscript`):
                        await printSubscript(`subscript`, level: level)
                    }
                } else {
                    await printObjCImportedMember(member, level: level)
                }
            }
        }
    }

    @SemanticStringBuilder
    private func printObjCImportedMember(_ member: ObjCImportedMemberDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: member.selector, kind: Self.printingKind(of: member))) {
            if member.hasExplicitSelector {
                Keyword(.atObjc)
                Standard("(\(member.selector))")
                Space()
            }
            if member.ownership == .copy {
                Keyword(.atNSCopying)
                Space()
            }
            if member.ownership == .weak {
                Keyword(.weak)
                Space()
            }
            if member.ownership == .unownedUnsafe {
                Keyword(.unowned)
                Standard("(")
                Keyword(.unsafe)
                Standard(")")
                Space()
            }
            if member.kind == .factoryInitializer {
                Keyword(.convenience)
                Space()
            }
            let node = member.node.materialize()
            switch member.kind {
            case .method, .initializer, .factoryInitializer:
                var printer = SemanticFunctionNodePrinter(isOverride: false, isClassMember: member.isClassMember, delegate: self)
                try await printer.printRoot(node)
            case .property:
                var printer = SemanticVariableNodePrinter(isStored: false, isOverride: false, isClassMember: member.isClassMember, hasSetter: member.isSettable, indentation: level, delegate: self)
                try await printer.printRoot(node)
            case .subscript:
                var printer = SemanticSubscriptNodePrinter(isOverride: false, isClassMember: member.isClassMember, hasSetter: member.isSettable, indentation: level, delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    /// A requirement of a protocol declared in Objective-C: the protocol is
    /// `@objc` as a whole, so a requirement spells `@objc` only to pin its
    /// selector.
    @SemanticStringBuilder
    private func printObjCImportedRequirement(_ requirement: ObjCProtocolRequirementDefinition, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: requirement.selector, kind: Self.printingKind(of: requirement))) {
            if requirement.hasExplicitSelector {
                Keyword(.atObjc)
                Standard("(\(requirement.selector))")
                Space()
            }
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

    // MARK: Helpers

    /// `: A, B, C` for the nodes of the names a declaration inherits.
    @SemanticStringBuilder
    private func inheritanceClause(_ nodes: [NodeReference]) async throws -> SemanticString {
        let resolver = typeDemangleResolver
        for (offset, node) in nodes.offsetEnumerated() {
            Standard(offset.isStart ? ":" : ",")
            Space()
            try await resolver.resolve(for: node.materialize())
        }
    }

    /// The Swift members of the definitions a class or category is paired
    /// with, indexed here — an index pass must not index another definition.
    private func implementingSwiftMembers(typeDefinitions: [TypeDefinition], extensionDefinitions: [ExtensionDefinition]) throws -> ObjCImplementingSwiftMembers {
        for typeDefinition in typeDefinitions {
            try typeDefinition.index(in: machO)
        }
        for extensionDefinition in extensionDefinitions {
            try extensionDefinition.index(in: machO)
        }
        return ObjCImplementingSwiftMembers(typeDefinitions: typeDefinitions, extensionDefinitions: extensionDefinitions)
    }

    /// A class's or protocol's own name, unqualified, as a header prints it.
    private static func leafName(of node: NodeReference, kind: Node.Kind) -> String? {
        node.materialize().first(of: kind)?.identifier
    }

    private static func printingKind(of member: ObjCImportedMemberDefinition) -> SwiftIndexEvents.PrintingDefinitionKind {
        switch member.kind {
        case .method, .initializer, .factoryInitializer: .function
        case .property: .variable
        case .subscript: .subscript
        }
    }

    private static func printingKind(of requirement: ObjCProtocolRequirementDefinition) -> SwiftIndexEvents.PrintingDefinitionKind {
        switch requirement.kind {
        case .method, .initializer: .function
        case .property: .variable
        case .subscript: .subscript
        }
    }
}

/// The Swift members of a class's or category's Swift definitions that
/// answer Objective-C selectors, by the selector the class's Objective-C
/// member table ties each to (`objcMember`). A tie by the `To` thunk symbol
/// or the thunk's code wins; a tie by name alone is taken when there is no
/// other — the definitions here implement the class, so a member whose name
/// is the importer's spelling of a selector of the class answers to it.
struct ObjCImplementingSwiftMembers {
    enum Member {
        case function(FunctionDefinition)
        case variable(VariableDefinition)
        case `subscript`(SubscriptDefinition)
    }

    private struct Key: Hashable {
        let selector: String
        let isClassMethod: Bool
    }

    private var joinedMembersByKey: [Key: Member] = [:]
    private var nameOnlyMembersByKey: [Key: Member] = [:]

    init(typeDefinitions: [TypeDefinition], extensionDefinitions: [ExtensionDefinition]) {
        for typeDefinition in typeDefinitions {
            add(
                functions: typeDefinition.functions + typeDefinition.staticFunctions + typeDefinition.allocators + typeDefinition.constructors,
                variables: typeDefinition.variables + typeDefinition.staticVariables,
                subscripts: typeDefinition.subscripts + typeDefinition.staticSubscripts
            )
        }
        for extensionDefinition in extensionDefinitions {
            add(
                functions: extensionDefinition.functions + extensionDefinition.staticFunctions + extensionDefinition.allocators + extensionDefinition.constructors,
                variables: extensionDefinition.variables + extensionDefinition.staticVariables,
                subscripts: extensionDefinition.subscripts + extensionDefinition.staticSubscripts
            )
        }
    }

    private mutating func add(functions: [FunctionDefinition], variables: [VariableDefinition], subscripts: [SubscriptDefinition]) {
        for function in functions {
            insert(function.objcMember, as: .function(function))
        }
        for variable in variables {
            insert(variable.objcMember, as: .variable(variable))
        }
        for `subscript` in subscripts {
            insert(`subscript`.objcMember, as: .subscript(`subscript`))
        }
    }

    private mutating func insert(_ objcMember: ObjCMember?, as member: Member) {
        guard let objcMember else { return }
        let key = Key(selector: objcMember.selector, isClassMethod: objcMember.isClassMethod)
        if objcMember.evidence == .selectorName {
            if nameOnlyMembersByKey[key] == nil {
                nameOnlyMembersByKey[key] = member
            }
        } else if joinedMembersByKey[key] == nil {
            joinedMembersByKey[key] = member
        }
    }

    /// The Swift member answering to `member`'s selector — a property's
    /// getter, or its setter when only that one is tied — or `nil`.
    func member(answering member: ObjCImportedMemberDefinition) -> Member? {
        // A factory method is a class method in Objective-C.
        let isClassMethod = member.isClassMember || member.kind == .factoryInitializer
        let keys = [member.selector, member.setterSelector].compactMap { $0 }.map { Key(selector: $0, isClassMethod: isClassMethod) }
        for membersByKey in [joinedMembersByKey, nameOnlyMembersByKey] {
            if let found = keys.lazy.compactMap({ membersByKey[$0] }).first {
                return found
            }
        }
        return nil
    }
}
