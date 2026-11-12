import SwiftDeclaration
import SwiftDeclarationRendering
@_spi(Internals) import Demangling
import Semantic
import SwiftInspection
import MachOSwiftSection
import MachOSymbols

/// How the interface prints what an attached macro generated (evolution
/// proposal `observable-macro-folding`). For a class `@Observable` expanded
/// (`TypeDefinition.observableMacroExpansion`), the folded form — the default
/// — reads the way the source does: `@Observation.Observable` on the class,
/// each tracked property as the stored `var x: T` it was declared as, in the
/// place of its storage `_x`, and a stored `var` the macro left alone with
/// `@Observation.ObservationIgnored`. The registrar, the computed properties
/// over the storage, the generated methods and the generated conformance are
/// left out. `SwiftDeclarationPrintConfiguration.expandsMacros` prints them
/// instead, as the binary has them; with `marksOptionalContent` both forms
/// print, each in a region conditioned on `SwiftVisibilityOption.expandsMacros`.
extension SwiftDeclarationPrinter {
    /// The rendering view of a definition's `@Observable` expansion for one
    /// print — derived from the model each time, never stored on it.
    struct ObservableMacroFolding: Sendable {
        /// Whether the definition carries an expansion: an indexed class
        /// `@Observable` expanded.
        var hasExpansion = false

        var trackedPropertiesByBackingFieldName: [String: ObservableMacroExpansion.TrackedProperty] = [:]

        /// The computed property each tracked property with accessors in the
        /// image is, by name.
        var trackedMemberVariablesByName: [String: VariableDefinition] = [:]

        /// The stored `var`s declared `@ObservationIgnored`, by field name.
        var ignoredStoredPropertyNames: Set<String> = []

        /// The wrapped properties declared `@ObservationIgnored` whose member
        /// variable prints them, by name.
        var observationIgnoredWrappedVariableNames: Set<String> = []

        var generatedFunctionSymbolNames: Set<String> = []

        static var none: ObservableMacroFolding { ObservableMacroFolding() }

        /// Whether `member` belongs to the expansion only: a computed
        /// property over a tracked property's storage, or a method the macro
        /// generated.
        func isExpansionOnly(_ member: OrderedMember) -> Bool {
            switch member {
            case .variable(let variable):
                return !variable.isGlobalOrStatic && trackedMemberVariablesByName[variable.name] != nil
            case .function(let function):
                return generatedFunctionSymbolNames.contains(function.symbol.name)
            default:
                return false
            }
        }

        /// Whether `field` belongs to the expansion only: the registrar.
        func isExpansionOnly(_ field: FieldDefinition) -> Bool {
            hasExpansion && field.name == ObservableMacroRecognition.registrarFieldName
        }

        func trackedProperty(storedIn field: FieldDefinition) -> ObservableMacroExpansion.TrackedProperty? {
            trackedPropertiesByBackingFieldName[field.name]
        }

        /// Whether `member` is a wrapped property the folded form prints with
        /// `@Observation.ObservationIgnored`.
        func isObservationIgnoredWrappedProperty(_ member: OrderedMember) -> Bool {
            guard case .variable(let variable) = member, !variable.isGlobalOrStatic else { return false }
            return observationIgnoredWrappedVariableNames.contains(variable.name)
        }
    }

    /// How a field prints: as the binary declares it, as the tracked property
    /// its storage is, or with `@Observation.ObservationIgnored`.
    enum ModelFieldForm: Sendable {
        case asDeclared
        case trackedProperty(ObservableMacroExpansion.TrackedProperty)
        case observationIgnored
    }

    /// Whether the type body prints, or only the fields and members a macro
    /// generated (`printMacroExpansion(of:attachedTo:level:)`).
    enum ModelMembersSelection: Sendable {
        case typeBody
        case observableMacroExpansion
    }

    func observableMacroFolding(of definition: some Definition) -> ObservableMacroFolding {
        guard let typeDefinition = definition as? TypeDefinition, let expansion = typeDefinition.observableMacroExpansion else { return .none }
        var folding = ObservableMacroFolding()
        folding.hasExpansion = true
        for trackedProperty in expansion.trackedProperties {
            folding.trackedPropertiesByBackingFieldName[trackedProperty.backingFieldName] = trackedProperty
            if trackedProperty.origin == .declaredMember,
               let memberVariable = typeDefinition.variables.first(where: { !$0.isGlobalOrStatic && $0.name == trackedProperty.name }) {
                folding.trackedMemberVariablesByName[trackedProperty.name] = memberVariable
            }
        }
        folding.ignoredStoredPropertyNames = Set(expansion.ignoredStoredPropertyNames)
        for wrappedProperty in typeDefinition.wrappedProperties where folding.ignoredStoredPropertyNames.contains(wrappedProperty.backingFieldName) {
            if case .declaredMember = wrappedProperty.origin {
                folding.observationIgnoredWrappedVariableNames.insert(wrappedProperty.name)
            }
        }
        folding.generatedFunctionSymbolNames = Set(expansion.generatedFunctions.map(\.symbol.name))
        return folding
    }

    // MARK: - Visibility

    /// Where content only the expansion prints goes: everywhere when the
    /// configuration expands macros, nowhere (`nil`) when it folds them, and
    /// when marking, in a region visible only while `expandsMacros` is on.
    func macroExpansionVisibility() -> VisibilityCondition? {
        if configuration.marksOptionalContent {
            return .enabled(SwiftVisibilityOption.expandsMacros.rawValue)
        }
        return configuration.expandsMacros ? .always : nil
    }

    /// Where content only the folded form prints goes; the counterpart of
    /// `macroExpansionVisibility()`.
    func foldedMacroVisibility() -> VisibilityCondition? {
        if configuration.marksOptionalContent {
            return .disabled(SwiftVisibilityOption.expandsMacros.rawValue)
        }
        return configuration.expandsMacros ? nil : .always
    }

    /// Both conditions at once, or `nil` — leave the content out — when
    /// either is. `always` adds nothing, so content printed unmarked stays
    /// unmarked.
    func combinedVisibility(_ first: VisibilityCondition?, _ second: VisibilityCondition?) -> VisibilityCondition? {
        guard let first, let second else { return nil }
        if first.isAlways { return second }
        if second.isAlways { return first }
        return .all([first, second])
    }

    // MARK: - Attributes

    /// `@Observation.Observable`, on its own line above the class, in an
    /// `AnnotationRegion` of the macro's kind when `marksAttachedMacros` is
    /// on. Printed from a name node like any other type reference, so module
    /// selectors reach it (`@Observation::Observable`).
    @SemanticStringBuilder
    func attachedMacroAttribute(_ macro: SwiftAttachedMacro, level: Int) async throws -> SemanticString {
        let attribute = try await macroAttribute(named: AttachedMacroNameNodes.attributeNameNode(of: macro), level: level)
        if configuration.marksAttachedMacros {
            AnnotationRegion(.attachedMacro(macro), content: attribute)
        } else {
            attribute
        }
    }

    /// `@Observation.ObservationIgnored ` — with the space — in front of a
    /// stored property the macro left alone.
    @SemanticStringBuilder
    func observationIgnoredAttribute(level: Int) async throws -> SemanticString {
        try await macroAttribute(named: AttachedMacroNameNodes.observationIgnored, level: level)
        Space()
    }

    @SemanticStringBuilder
    private func macroAttribute(named nameNode: Node, level: Int) async throws -> SemanticString {
        Standard("@")
        try await printThrowingType(nameNode, isProtocol: false, level: level)
    }

    // MARK: - Declarations

    /// `var x: T` for a tracked property, from its storage `_x`: the storage's
    /// `weak` / `unowned` keyword and type, under the property's own name,
    /// `final` when the computed property the macro generated is.
    @SemanticStringBuilder
    func printThrowingTrackedProperty(_ trackedProperty: ObservableMacroExpansion.TrackedProperty, storedIn field: FieldDefinition, memberVariable: VariableDefinition?, level: Int, substitutedTypeNode: Node?) async throws -> SemanticString {
        if memberVariable?.isFinal == true {
            Keyword(.final)
            Space()
        }
        fieldDeclarationKeywords(for: field.flags)
        MemberDeclaration(trackedProperty.name)
        Standard(":")
        Space()
        try await printThrowingType(fieldTypeNode(for: field, substitutedTypeNode: substitutedTypeNode), isProtocol: false, level: level)
    }

    /// A member variable's declaration with `@Observation.ObservationIgnored`
    /// in front of it, as one row.
    @SemanticStringBuilder
    func printObservationIgnoredVariable(_ variable: VariableDefinition, level: Int, propertyWrapperAttributeTypeNode: Node?) async -> SemanticString {
        if let attribute = await printCatchedThrowing(dispatchingTo: eventDispatcher, { try await observationIgnoredAttribute(level: level) }) {
            attribute
        }
        await printVariable(variable, level: level, propertyWrapperAttributeTypeNode: propertyWrapperAttributeTypeNode)
    }

    /// `member` in a type body under the `@Observable` folding, given the
    /// visibility the exported-only filter gives it: a member of the
    /// expansion only where the expansion prints, a wrapped property the
    /// source declared `@ObservationIgnored` with the attribute in the folded
    /// form and without it in the expansion, anything else as it is. `render`
    /// prints the member, with the attribute or not; each form is one item
    /// of the caller's list.
    @SemanticStringBuilder
    func renderMember(_ member: OrderedMember, visibleUnder visibility: VisibilityCondition, folding: ObservableMacroFolding, render: (_ marksObservationIgnored: Bool) async -> SemanticString) async -> SemanticString {
        if folding.isExpansionOnly(member) {
            if let expansionVisibility = combinedVisibility(visibility, macroExpansionVisibility()) {
                await render(false).visible(under: expansionVisibility)
            }
        } else if folding.isObservationIgnoredWrappedProperty(member) {
            if let foldedVisibility = combinedVisibility(visibility, foldedMacroVisibility()) {
                await render(true).visible(under: foldedVisibility)
            }
            if let expansionVisibility = combinedVisibility(visibility, macroExpansionVisibility()) {
                await render(false).visible(under: expansionVisibility)
            }
        } else {
            await render(false).visible(under: visibility)
        }
    }

    // MARK: - The expansion on its own

    /// What `macro` generated in `typeDefinition`, as one block of
    /// declarations, the way `expandsMacros` prints each of them inside the
    /// type: for `.observable`, the storage `_x` of each tracked property and
    /// the registrar in field order, the computed properties over the
    /// storage that the image keeps accessors of, `access(keyPath:)`,
    /// `withMutation(keyPath:_:)` and the `shouldNotifyObservers(_:_:)`
    /// overloads the image keeps, then the conformance the macro generated
    /// (evolution proposal `observable-macro-folding`).
    ///
    /// Everything the configuration decides applies as for the type —
    /// comments, transformers, the exported-only filter, module selectors,
    /// marking — except `expandsMacros`, which this ignores: the expansion is
    /// what it prints. The members print at `level`, the indentation of the
    /// type's members, the conformance at `level - 1`, the type's own; the
    /// block has no leading or trailing line break. Empty when the type does
    /// not carry `macro`. Indexes the definition, as `printTypeDefinition`
    /// does.
    public func printMacroExpansion(of macro: SwiftAttachedMacro, attachedTo typeDefinition: TypeDefinition, level: Int = 1) async throws -> SemanticString {
        guard macro == .observable, typeDefinition.attachedMacros.contains(.observable) else { return SemanticString() }
        return try await LargeStackTaskExecution.run {
            try typeDefinition.index(in: machO)
            guard typeDefinition.observableMacroExpansion != nil else { return SemanticString() }
            return try await printIncludedObservableMacroExpansion(of: typeDefinition, level: level)
        }
    }

    private func printIncludedObservableMacroExpansion(of typeDefinition: TypeDefinition, level: Int) async throws -> SemanticString {
        // This print operation's single wrapper materialization (proposal
        // 0002), as `printTypeDefinition` does.
        let materializedTypeContext = try typeDefinition.materializedTypeContext(in: machO.context)
        // The extended type's name node outlives the print: the type printer
        // memoizes fragments by node identity.
        let extendedTypeNameNode = typeDefinition.typeName.node.materialize()

        let fieldDeclarations = try await renderedModelFieldDeclarations(typeDefinition, typeContext: materializedTypeContext, level: level, selection: .observableMacroExpansion).map(\.declaration)
        let memberDeclarations = await renderedMacroExpansionMembers(of: typeDefinition, level: level, includesTrackedProperties: true)
        let conformance = try await printThrowingGeneratedConformance(extendingTypeNamed: extendedTypeNameNode, level: level)
        // One declaration a row, each carrying its own indentation: the rows
        // put a line break between two of them exactly where both are
        // visible, so a marked print projects to the block printed with the
        // same options, and the block opens and closes on a declaration.
        return SemanticString(Rows(level: 0, fieldDeclarations + memberDeclarations + [conformance]))
    }

    /// What `macro` generated in `typeDefinition`, in the pieces a host places
    /// where Xcode's Expand Macro shows an attached macro's expansion
    /// (evolution proposal `observable-macro-folding`): for `.observable`, one
    /// piece below each tracked property's folded declaration — the accessor
    /// block of the computed property the macro generated as the expanded
    /// form prints it, when the image keeps its accessors, then the storage
    /// `_x` — in the order the type body prints them; one above the type's
    /// closing brace — the registrar and the generated methods; and one below
    /// it — the generated conformance. See `MacroExpansionPart` for where
    /// each goes.
    ///
    /// Each piece is printed the way `printMacroExpansion(of:attachedTo:level:)`
    /// prints its declarations — every configuration rule but
    /// `expandsMacros` applies — without indentation of its own and without
    /// a line break around it. A piece with nothing left to print is left
    /// out. Empty when the type does not carry `macro`. Indexes the
    /// definition, as `printTypeDefinition` does.
    public func printMacroExpansionParts(of macro: SwiftAttachedMacro, attachedTo typeDefinition: TypeDefinition) async throws -> [MacroExpansionPart] {
        guard macro == .observable, typeDefinition.attachedMacros.contains(.observable) else { return [] }
        return try await LargeStackTaskExecution.run {
            try typeDefinition.index(in: machO)
            guard let expansion = typeDefinition.observableMacroExpansion else { return [] }
            return try await printIncludedObservableMacroExpansionParts(of: typeDefinition, expansion: expansion)
        }
    }

    private func printIncludedObservableMacroExpansionParts(of typeDefinition: TypeDefinition, expansion: ObservableMacroExpansion) async throws -> [MacroExpansionPart] {
        // This print operation's single wrapper materialization (proposal
        // 0002), and the extended type's name node, which outlives the print.
        let materializedTypeContext = try typeDefinition.materializedTypeContext(in: machO.context)
        let extendedTypeNameNode = typeDefinition.typeName.node.materialize()
        let folding = observableMacroFolding(of: typeDefinition)

        // Level 0: a piece carries no indentation of its own.
        var fieldDeclarationsByName: [String: SemanticString] = [:]
        for fieldDeclaration in try await renderedModelFieldDeclarations(typeDefinition, typeContext: materializedTypeContext, level: 0, selection: .observableMacroExpansion) {
            fieldDeclarationsByName[fieldDeclaration.fieldName] = fieldDeclaration.declaration
        }

        var parts: [MacroExpansionPart] = []
        for trackedProperty in expansion.trackedProperties {
            var rows: [SemanticString] = []
            if let memberVariable = folding.trackedMemberVariablesByName[trackedProperty.name],
               let visibility = exportFilterVisibility(excluded: isExcludedByExportFilter(.variable(memberVariable))) {
                rows.append(accessorBlock(of: memberVariable).visible(under: visibility))
            }
            if let storage = fieldDeclarationsByName[trackedProperty.backingFieldName] {
                rows.append(storage)
            }
            guard !rows.isEmpty else { continue }
            parts.append(MacroExpansionPart(macro: .observable, placement: .trackedProperty(named: trackedProperty.name), content: SemanticString(Rows(level: 0, rows))))
        }

        var memberRows: [SemanticString] = []
        if let registrar = fieldDeclarationsByName[ObservableMacroRecognition.registrarFieldName] {
            memberRows.append(registrar)
        }
        memberRows += await renderedMacroExpansionMembers(of: typeDefinition, level: 0, includesTrackedProperties: false)
        if !memberRows.isEmpty {
            parts.append(MacroExpansionPart(macro: .observable, placement: .members, content: SemanticString(Rows(level: 0, memberRows))))
        }

        // Level 1: the conformance prints at the type's own indentation, one
        // level out from its members.
        let conformance = try await printThrowingGeneratedConformance(extendingTypeNamed: extendedTypeNameNode, level: 1)
        parts.append(MacroExpansionPart(macro: .observable, placement: .conformance, content: conformance))
        return parts
    }

    /// The accessor block a member variable's declaration ends with, as the
    /// expanded form prints it — `{`, `get` and `set` one level in, `}` — on
    /// its own.
    @SemanticStringBuilder
    private func accessorBlock(of variable: VariableDefinition) -> SemanticString {
        let keywords = AccessorBlockKeywords(of: variable)
        Standard("{")
        BreakLine()
        Indent(level: 1)
        Keyword(keywords.read)
        if let write = keywords.write {
            BreakLine()
            Indent(level: 1)
            Keyword(write)
        }
        BreakLine()
        Standard("}")
    }

    /// The members of `typeDefinition`'s expansion, each a row of its own —
    /// its comments and its declaration, indented to `level` — in the order
    /// the type body prints them, under the exported-only filter. Without
    /// `includesTrackedProperties`, the computed properties over the storage
    /// are left out: their accessor blocks go into each property's piece.
    private func renderedMacroExpansionMembers(of typeDefinition: TypeDefinition, level: Int, includesTrackedProperties: Bool) async -> [SemanticString] {
        let folding = observableMacroFolding(of: typeDefinition)
        let members: [OrderedMember]
        switch configuration.memberSortOrder {
        case .byOffset:
            members = typeDefinition.orderedMembers
        case .byCategory:
            let allMembers = OrderedMember.allMembers(from: typeDefinition)
            members = OrderedMember.vtableOrdered(allMembers) + MemberCategory.allCases.flatMap { category in
                typeDefinition.members(in: category).filter { $0.minVTableOffset == nil }
            }
        }
        let renderingContext = memberRenderingContext(of: typeDefinition, isProtocol: false)
        var renderedMembers: [SemanticString] = []
        for member in members where folding.isExpansionOnly(member) {
            if !includesTrackedProperties, case .variable = member { continue }
            guard let visibility = exportFilterVisibility(excluded: isExcludedByExportFilter(member)) else { continue }
            let rendered = await renderMember(member, level: level, context: renderingContext, marksObservationIgnored: false)
            renderedMembers.append((SemanticString(Indent(level: level)) + rendered).visible(under: visibility))
        }
        return renderedMembers
    }

    /// `extension Model: Observation.Observable {}`, the conformance
    /// `@Observable` generates — a fixed form: the macro writes no `where`
    /// clause and no member into it.
    @SemanticStringBuilder
    private func printThrowingGeneratedConformance(extendingTypeNamed extendedTypeNameNode: Node, level: Int) async throws -> SemanticString {
        Indent(level: level - 1)
        Keyword(.extension)
        Space()
        try await printThrowingType(extendedTypeNameNode, isProtocol: false, level: level)
        Standard(":")
        Space()
        try await printThrowingType(AttachedMacroNameNodes.observableProtocol, isProtocol: false, level: level)
        Space()
        Standard("{}")
    }
}

/// The name nodes the folded form and the expansion print, shared with the
/// dump (`ObservableMacroRecognition`).
enum AttachedMacroNameNodes {
    static var observableProtocol: Node { ObservableMacroRecognition.observableAttributeNameNode }

    static var observationIgnored: Node { ObservableMacroRecognition.observationIgnoredAttributeNameNode }

    static func attributeNameNode(of macro: SwiftAttachedMacro) -> Node {
        // `.observable` is the one macro recognized; another gets a static
        // node of its own beside it.
        precondition(macro == .observable, "no attribute name node for \(macro.moduleName).\(macro.name)")
        return observableProtocol
    }
}
