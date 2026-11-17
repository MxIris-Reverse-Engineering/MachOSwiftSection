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
    /// A class Swift implements prints as its Swift side (evolution proposal
    /// `swift-first-imported-declarations`). A Swift class prints as the
    /// Swift class it is, followed by its extensions in the image and an
    /// `extension` of the Objective-C methods no member of them answers to.
    /// An `@objc @implementation` class prints the implementation's body —
    /// as the Swift interface prints it, its `final` members too — under the
    /// class's own declaration, the Objective-C methods no Swift member
    /// answers to last, and the image's other extensions of it after it. A
    /// class implemented in Objective-C prints its method list in order, each
    /// member a Swift extension of it answers to as that Swift member and the
    /// rest by the rules.
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

    /// The members of `definition` a header marks `NS_REFINED_FOR_SWIFT`, as
    /// far as the image's Swift side shows (evolution proposal
    /// `swift-first-imported-declarations`): one a Swift member named with
    /// the importer's `__` prefix answers to, and a property no Swift member
    /// answers to whose plain name a Swift property of another type has
    /// taken. The binary keeps no trace of the macro; a host printing the
    /// header puts it back from these. Empty for a Swift class, which has no
    /// header, and for a class no Swift definition implements or extends.
    public func objcMembersRefinedForSwift(in definition: ObjCImportedClassDefinition) throws -> [ObjCRefinedForSwiftMember] {
        try definition.index(in: machO)
        guard definition.swiftClassDefinition == nil, !definition.swiftExtensions.isEmpty else { return [] }
        let swiftMembers = try implementingSwiftMembers(of: definition.members, typeDefinitions: [], extensionDefinitions: definition.swiftExtensions, recognizesRefinements: true)
        return definition.members.indices.compactMap { index in
            swiftMembers.refinement(ofMemberAt: index).map { ObjCRefinedForSwiftMember(member: definition.members[index], refinement: $0) }
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
            let swiftMembers = try implementingSwiftMembers(of: definition.members, typeDefinitions: [swiftClassDefinition], extensionDefinitions: definition.swiftExtensions, recognizesRefinements: false)
            let unansweredMembers = definition.members.indices.filter { swiftMembers.member(answeringMemberAt: $0) == nil }.map { definition.members[$0] }
            // Its extensions trail it, as in the module's interface.
            await BlockList {
                for extensionDefinition in definition.swiftExtensions {
                    await printCatchedThrowing(
                        dispatchingTo: eventDispatcher,
                        context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                    ) {
                        try await printExtensionDefinition(extensionDefinition)
                    }
                }
                if !unansweredMembers.isEmpty {
                    await printCatchedThrowing(
                        dispatchingTo: eventDispatcher,
                        context: .init(name: definition.className.name, kind: .extension)
                    ) {
                        try await DeclarationBlock(level: level) {
                            Keyword(.extension)
                            Space()
                            renderExtendedTypeName(definition.className.extensionName)
                        } body: {
                            try await MemberList(level: level) {
                                comment(.note("Objective-C methods of the class that no member of the Swift class answers to. Swift names follow the ClangImporter's rules for these selectors."), as: .note)
                                for member in unansweredMembers {
                                    await printObjCImportedMember(member, level: level)
                                }
                            }
                        }
                    }
                }
            }
        } else if definition.swiftExtensions.contains(where: { $0.objcImplementation != nil }) {
            try await printObjCImplementationClass(definition, level: level)
        } else {
            let swiftMembers = try implementingSwiftMembers(of: definition.members, typeDefinitions: [], extensionDefinitions: definition.swiftExtensions, recognizesRefinements: true)
            try await DeclarationBlock(level: level) {
                try await importedClassDeclaration(definition)
            } body: {
                try await objcImportedMemberList(definition.members, swiftMembers: swiftMembers, level: level)
            }
        }

        eventDispatcher.dispatch(.definitionPrintCompleted(context: printingContext))
    }

    /// An `@objc @implementation` class as its Swift side (evolution proposal
    /// `swift-first-imported-declarations`): the class's own declaration —
    /// superclass and protocols from the Objective-C record — around the
    /// implementation's body as the Swift interface prints it, then the
    /// Objective-C methods no Swift member answers to; the image's other
    /// Swift extensions of the class trail it. A stored property whose Swift
    /// type the image does not record prints as the Objective-C property
    /// synthesized on it, where the Swift interface can only describe the
    /// ivar in a comment.
    @SemanticStringBuilder
    private func printObjCImplementationClass(_ definition: ObjCImportedClassDefinition, level: Int) async throws -> SemanticString {
        let swiftMembers = try implementingSwiftMembers(of: definition.members, typeDefinitions: [], extensionDefinitions: definition.swiftExtensions, recognizesRefinements: true)
        let implementationExtensions = definition.swiftExtensions.filter { $0.objcImplementation != nil }
        let otherExtensions = definition.swiftExtensions.filter { $0.objcImplementation == nil }
        let standInIndices = Self.memberIndicesStandingIn(forInstanceVariablesOf: implementationExtensions, members: definition.members, swiftMembers: swiftMembers)
        let standIns = standInIndices.mapValues { definition.members[$0] }
        let standInIndexSet = Set(standInIndices.values)
        let trailingIndices = definition.members.indices.filter { swiftMembers.member(answeringMemberAt: $0) == nil && !standInIndexSet.contains($0) }
        try await DeclarationBlock(level: level) {
            try await importedClassDeclaration(definition)
        } body: {
            for extensionDefinition in implementationExtensions {
                try await printExtensionBodyContents(extensionDefinition, level: level) {
                    await renderUnrepresentedObjCImplementationInstanceVariables(extensionDefinition, level: 1, standIns: standIns)
                }
            }
            if !trailingIndices.isEmpty {
                await MemberList(level: level) {
                    comment(.note("Objective-C methods of the class that no Swift member answers to. Swift names follow the ClangImporter's rules for these selectors."), as: .note)
                    for index in trailingIndices {
                        await printUnansweredObjCImportedMember(definition.members[index], refinement: swiftMembers.refinement(ofMemberAt: index), level: level)
                    }
                }
            }
        }
        // Its other extensions trail it, as in the module's interface.
        await BlockList {
            for extensionDefinition in otherExtensions {
                await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                ) {
                    try await printExtensionDefinition(extensionDefinition)
                }
            }
        }
    }

    /// `class Name: Superclass, Protocol…`, from the Objective-C record.
    @SemanticStringBuilder
    private func importedClassDeclaration(_ definition: ObjCImportedClassDefinition) async throws -> SemanticString {
        Keyword(.class)
        Space()
        TypeDeclaration(kind: .class, Self.leafName(of: definition.className.node, kind: .class) ?? definition.objcRuntimeName)
        try await inheritanceClause([definition.superclassName?.node].compactMap { $0 } + definition.protocolNames.map(\.node))
    }

    /// The Objective-C property each stored property of an `@objc
    /// @implementation` stands in for, by the ivar's identity: the one
    /// synthesized on an ivar whose Swift type the image does not record, and
    /// that no Swift member answers to.
    private static func memberIndicesStandingIn(forInstanceVariablesOf implementationExtensions: [ExtensionDefinition], members: [ObjCImportedMemberDefinition], swiftMembers: ObjCImplementingSwiftMembers) -> [ObjectIdentifier: Int] {
        var indicesByInstanceVariable: [ObjectIdentifier: Int] = [:]
        for extensionDefinition in implementationExtensions {
            guard let facts = extensionDefinition.objcImplementation else { continue }
            for instanceVariable in extensionDefinition.unrepresentedObjCImplementationInstanceVariables where instanceVariable.swiftTypeNode == nil && !instanceVariable.name.isEmpty {
                guard let property = facts.properties.first(where: { $0.instanceVariableName == instanceVariable.name }),
                      let index = members.indices.first(where: { members[$0].kind == .property && !members[$0].isClassMember && members[$0].objcPropertyName == property.name && swiftMembers.member(answeringMemberAt: $0) == nil })
                else { continue }
                indicesByInstanceVariable[ObjectIdentifier(instanceVariable)] = index
            }
        }
        return indicesByInstanceVariable
    }

    // MARK: Categories

    @SemanticStringBuilder
    private func printIncludedObjCImportedCategoryDefinition(_ definition: ObjCImportedCategoryDefinition, level: Int) async throws -> SemanticString {
        let printingContext = SwiftIndexEvents.PrintingContext(name: definition.uniqueName, kind: .extension)
        eventDispatcher.dispatch(.definitionPrintStarted(context: printingContext))

        try definition.index(in: machO)
        let swiftMembers = try implementingSwiftMembers(of: definition.members, typeDefinitions: [], extensionDefinitions: definition.swiftExtensions, recognizesRefinements: false)

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
            if members.indices.contains(where: { swiftMembers.member(answeringMemberAt: $0) == nil }) {
                comment(.note("Swift names follow the ClangImporter's rules for these selectors; the binary records no Swift names for them."), as: .note)
            }
            for (index, member) in members.enumerated() {
                if let swiftMember = swiftMembers.member(answeringMemberAt: index) {
                    switch swiftMember {
                    case .function(let function):
                        await printFunction(function, level: level)
                    case .variable(let variable):
                        await printVariable(variable, level: level)
                    case .subscript(let `subscript`):
                        await printSubscript(`subscript`, level: level)
                    }
                } else {
                    await printUnansweredObjCImportedMember(member, refinement: swiftMembers.refinement(ofMemberAt: index), level: level)
                }
            }
        }
    }

    /// An Objective-C member no Swift member answers to, by the importer's
    /// rules — or, for a property whose plain name a Swift declaration of
    /// another type has taken, the declaration Swift gives it under
    /// `NS_REFINED_FOR_SWIFT`, as a comment: the image keeps no symbol of it,
    /// and the prefixed name is the importer's rule, not the binary's word
    /// (evolution proposal `swift-first-imported-declarations`).
    @SemanticStringBuilder
    private func printUnansweredObjCImportedMember(_ member: ObjCImportedMemberDefinition, refinement: ObjCImplementingSwiftMembers.Refinement?, level: Int) async -> SemanticString {
        if refinement == .nameTakenByAnotherDeclaration, let refinedMember = refinedForSwiftMember(of: member) {
            let declaration = await printObjCImportedMember(refinedMember, level: level).string
            comment(.refinedForSwiftMember(declaration: declaration), as: .refinedForSwiftMember)
        } else {
            await printObjCImportedMember(member, level: level)
        }
    }

    /// `member`, a property, under the name Swift gives a property the header
    /// marks `NS_REFINED_FOR_SWIFT`; `nil` for any other member. The selector
    /// stays the Objective-C one, which the prefixed name does not derive, so
    /// no `@objc(selector)` is spelled: the importer pairs them.
    private func refinedForSwiftMember(of member: ObjCImportedMemberDefinition) -> ObjCImportedMemberDefinition? {
        guard member.kind == .property, let node = Self.refinedForSwiftPropertyNode(member.node.materialize()) else { return nil }
        return ObjCImportedMemberDefinition(
            kind: member.kind,
            node: InternedNodeReferenceCache.shared.reference(interning: node, in: machO),
            selector: member.selector,
            setterSelector: member.setterSelector,
            isClassMember: member.isClassMember,
            ownership: member.ownership,
            hasExplicitSelector: false,
            typeEncoding: member.typeEncoding,
            objcPropertyName: member.objcPropertyName
        )
    }

    /// `node` — a property's `Global > [Static >] Getter > Variable` — with
    /// `ObjCMemberShape.refinedForSwiftPrefix` in front of the property's
    /// name; `nil` when it holds no named `Variable`.
    private static func refinedForSwiftPropertyNode(_ node: Node) -> Node? {
        var children = Array(node.children)
        if node.kind == .variable {
            guard let identifierIndex = children.firstIndex(where: { $0.kind == .identifier }), let name = children[identifierIndex].text else { return nil }
            children[identifierIndex] = Node.createTransient(kind: .identifier, text: ObjCMemberShape.refinedForSwiftPrefix + name)
            return Node.createTransient(kind: .variable, children: children)
        }
        guard let childIndex = children.firstIndex(where: { $0.kind == .variable || $0.first(of: .variable) != nil }),
              let renamedChild = refinedForSwiftPropertyNode(children[childIndex])
        else { return nil }
        children[childIndex] = renamedChild
        return Node.createTransient(kind: node.kind, children: children)
    }

    @SemanticStringBuilder
    func printObjCImportedMember(_ member: ObjCImportedMemberDefinition, level: Int) async -> SemanticString {
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
    private func implementingSwiftMembers(of objcMembers: [ObjCImportedMemberDefinition], typeDefinitions: [TypeDefinition], extensionDefinitions: [ExtensionDefinition], recognizesRefinements: Bool) throws -> ObjCImplementingSwiftMembers {
        for typeDefinition in typeDefinitions {
            try typeDefinition.index(in: machO)
        }
        for extensionDefinition in extensionDefinitions {
            try extensionDefinition.index(in: machO)
        }
        return ObjCImplementingSwiftMembers(objcMembers: objcMembers, typeDefinitions: typeDefinitions, extensionDefinitions: extensionDefinitions, recognizesRefinements: recognizesRefinements)
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
