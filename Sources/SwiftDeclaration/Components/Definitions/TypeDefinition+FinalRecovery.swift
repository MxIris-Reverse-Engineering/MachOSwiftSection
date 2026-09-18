import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

extension TypeDefinition {
    /// `final` recovery (evolution proposal 0006) — the mirror image of the
    /// `class`/`static` recovery documented in ClassMemberKeywordRecovery.md:
    /// a class member with no vtable method descriptor has no dynamic
    /// dispatch entry, which is exactly what declaring it `final` compiles
    /// to. Two exclusions keep the honest side of the ledger: a member
    /// whose accessor symbols never joined stays unmarked (absence of
    /// evidence is not `final`), and an `@objc` member without a descriptor
    /// dispatches through the ObjC runtime (`@objc dynamic`) — overridable,
    /// so never `final`.
    ///
    /// Only a caller holding `ClassDispatchLookups.canRecoverFinalMembers`
    /// may run this. Its position in `index(in:)` is load-bearing twice over:
    /// after `applyThunkAttributes` (which supplies the `@objc` evidence) and
    /// before `orderedMembers` is built (which copies the member values).
    func recoverFinalMembers(
        fields: inout [FieldDefinition],
        symbolIndexStore: SymbolIndexStore,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) {
        let name = typeName.name
        let node = typeName.node
        // Node-matched, like `applyThunkAttributes` above: this gate
        // SUPPRESSES `final`, so a same-named private sibling's `@objc`
        // member would silently strip the keyword off this type's
        // genuinely final member (issue #115's family).
        let objcThunkMemberNames = Set(symbolIndexStore.thunkAttributeMembers(of: .objCAttribute, for: name, node: node, in: machO).filter { !$0.isStatic }.map(\.memberName))
        // Fourth gate — `Tq` method-descriptor SYMBOLS as negative
        // evidence: they are per-member data symbols at unique addresses,
        // immune to the identical-code-folding that defeats the
        // descriptor→implementation-symbol join (SourceEditor folds 1128
        // empty implementations onto one address, where the join cannot
        // pair descriptors with members and every folded member would
        // read as `final`). A member name with a `Tq` symbol provably has
        // a vtable entry — never `final`, even when the join missed it.
        var methodDescriptorSymbolMemberNames: Set<String> = []
        var subscriptMethodDescriptorNodeKeys: Set<StructuralNodeReferenceKey> = []
        let instanceMemberKinds: [SymbolIndexStore.MemberKind] = [
            .function(inExtension: false, isStatic: false),
            .variable(inExtension: false, isStatic: false, isStorage: false),
            .subscript(inExtension: false, isStatic: false),
        ]
        for kind in instanceMemberKinds {
            // Node-matched for the same reason as the `@objc` gate above:
            // a sibling's `Tq` descriptor under the stripped name would
            // read as this type's vtable evidence and suppress `final`.
            for descriptorSymbol in symbolIndexStore.methodDescriptorMemberSymbols(of: kind, for: name, node: node, in: machO) {
                if let functionName = descriptorSymbol.demangledNode.first(of: .function)?.identifier {
                    methodDescriptorSymbolMemberNames.insert(functionName)
                } else if let variableName = descriptorSymbol.demangledNode.first(of: .variable)?.identifier {
                    methodDescriptorSymbolMemberNames.insert(variableName)
                } else if let subscriptNode = descriptorSymbol.demangledNode.first(of: .subscript) {
                    // Overloaded subscripts share one name, so they key on
                    // the subscript subtree — the same extraction
                    // `DefinitionBuilder.subscripts` groups accessors by.
                    subscriptMethodDescriptorNodeKeys.insert(StructuralNodeReferenceKey(subscriptNode))
                }
            }
        }
        for index in functions.indices where functions[index].methodDescriptor == nil && !functions[index].attributes.contains(.objc) && !methodDescriptorSymbolMemberNames.contains(functions[index].name) {
            functions[index].isFinal = true
        }
        for index in variables.indices where !variables[index].accessors.isEmpty && !variables[index].hasVTableAccessor && !variables[index].attributes.contains(.objc) && !methodDescriptorSymbolMemberNames.contains(variables[index].name) {
            variables[index].isFinal = true
        }
        for index in subscripts.indices where !subscripts[index].accessors.isEmpty && !subscripts[index].hasVTableAccessor && !subscripts[index].attributes.contains(.objc) {
            let subscriptNodeKey = subscripts[index].node.first(of: .subscript).map { StructuralNodeReferenceKey($0) }
            if let subscriptNodeKey, subscriptMethodDescriptorNodeKeys.contains(subscriptNodeKey) { continue }
            subscripts[index].isFinal = true
        }
        // Stored `let`s are not overridable to begin with, so `final` on
        // them is pure noise — only stored `var`s (field records carrying
        // the IsVar flag) participate.
        for index in fields.indices where fields[index].flags.contains(.isVariable) && !fields[index].accessors.isEmpty && !fields[index].hasVTableAccessor && !objcThunkMemberNames.contains(fields[index].name) && !methodDescriptorSymbolMemberNames.contains(fields[index].name) {
            fields[index].isFinal = true
        }
    }
}
