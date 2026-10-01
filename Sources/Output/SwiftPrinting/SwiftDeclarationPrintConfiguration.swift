import SwiftDeclaration
import MemberwiseInit
import Semantic
import SwiftDeclarationRendering
import MachOSwiftSection

public enum SwiftDeclarationMemberSortOrder: Hashable, Codable, Sendable, CaseIterable {
    /// Group members by category: allocators, variables, functions, subscripts, then static members.
    /// A class's vtable members come first, in vtable slot order — for its own slots, the source's
    /// declaration order — and only the members that own no slot are grouped.
    case byCategory
    /// Sort members by binary layout offset (vtable/PWT/MachO offset depending on context).
    case byOffset
}

@MemberwiseInit(.public)
public struct SwiftDeclarationPrintConfiguration: Equatable, Sendable {
    public var printStrippedSymbolicItem: Bool = true
    public var printFieldOffset: Bool = false
    public var printExpandedFieldOffsets: Bool = false
    public var printMemberAddress: Bool = false
    public var printVTableOffset: Bool = false
    public var printPWTOffset: Bool = false

    /// Emit a `// not exported` comment on members none of whose symbols
    /// have an export-trie entry (evolution proposal 0008). A symbol-table
    /// FACT, not an access-level guess; nothing is emitted when the image
    /// carries no export information.
    public var printExportStatus: Bool = false

    /// Print only the declarations the image EXPORTS (evolution proposal
    /// `exported-only-interface`) — the filtering counterpart of
    /// `printExportStatus`. Types / protocols are ruled by their descriptor
    /// symbol (`…Mn` / `…Mp`) in the export trie, members by the same
    /// derived-form verdict the annotation uses, extensions by whether their
    /// target is an in-image non-exported declaration (see
    /// `ExportFilterScope`). Still a symbol-table FACT: a declaration is
    /// dropped only on a definitive negative — anything without evidence
    /// (no export information, no joined symbols, `override` / `@objc`
    /// members) is kept, so the filter never drops on a guess.
    public var printExportedDeclarationsOnly: Bool = false

    /// Whether to act on the ObjC member recovery's NAME-only evidence tier
    /// (evolution proposal `objc-member-selector-recovery`): an overriding
    /// ObjC method neither joining tier could tie to a Swift member — its IMP
    /// carries no `To` thunk symbol and its code references no Swift symbol,
    /// the optimizer having inlined the body into the thunk (`viewDidHide`,
    /// `encodeWithCoder:` in an OS framework) — was attributed at index time
    /// to the ONE member of the class whose name is the importer's spelling
    /// of its selector. The index always records it; set this to print the
    /// `@objc override` it implies.
    ///
    /// Off by default: the interface has nowhere to say which keyword rests
    /// on a name rather than a symbol, where the dump marks the same tie
    /// `(selector name, no symbol evidence)` and so always renders it. Only
    /// ever supplies an override — a method no ancestor implements is left
    /// alone, so this can never invent an `@objc(name)`.
    public var infersObjCOverridesFromSelectorNames: Bool = false
    public var memberSortOrder: SwiftDeclarationMemberSortOrder = .byCategory
    public var printTypeLayout: Bool = false
    public var printEnumLayout: Bool = false

    /// Print everything the options named by `SwiftVisibilityOption` control,
    /// each piece marked with a `VisibilityRegion` conditioned on its option,
    /// instead of letting those options decide (evolution proposal
    /// `visibility-regions`). A marked interface, frozen, separated and
    /// projected with `isVisibilityOptionEnabled(_:resolvesOpaqueTypes:)` of
    /// some configuration, reads byte for byte as printing with that
    /// configuration. Everything else here — the transformers, the sort
    /// order, the export options — applies as usual.
    ///
    /// For the opaque type constraints to be there to mark, register the
    /// opaque type resolver as for a normal print.
    public var marksOptionalContent: Bool = false

    /// Wrap every nested type and protocol printed inside its parent — a
    /// type's nested definitions and an extension's — in a
    /// `DefinitionRegion` named after the definition (evolution proposal
    /// `nested-definition-regions`). The identity is the mangled name of the
    /// definition's name node: `mangleAsString(typeName.node)`, or
    /// `mangleAsString(protocolName.node)` for a protocol.
    ///
    /// The contract: in the frozen print of a parent printed at the default
    /// `level` 1, a region at depth `d`, taken out with
    /// `content(ofDefinitionRegion:)` and then
    /// `removingIndentation(levels: d + 1)`, equals the frozen print of that
    /// definition on its own with the same printer — text, spans,
    /// identifiers, and with `marksOptionalContent` the regions its
    /// visibility separation finds. So a host that needs every nested
    /// definition on its own prints the parent once instead of printing each
    /// child again.
    ///
    /// A child whose print throws is dropped from its parent, as without
    /// marking, and leaves no region; a name that does not remangle, or
    /// remangles to text a region identity cannot carry, prints unmarked.
    /// The host prints such a child on its own. The contract holds for the
    /// built-in rendering and for transformers installed by
    /// `applyTransformers(_:)`; a hand-written transformer closure must start
    /// each line it emits with the indentation it is given.
    ///
    /// Off by default, and off the output is unchanged byte for byte.
    public var marksNestedDefinitions: Bool = false

    /// How the static (`MachOFile`) field-layout path resolves cross-module
    /// types when a layout-bearing flag is on. Defaults to the full transitive
    /// dependency closure over the system dyld shared cache; set `.singleImage`
    /// to restrict resolution to the binary being printed.
    public var staticLayoutDependencyResolution: StaticLayoutDependencyResolution = .default

    public var memberAddressTransformer: MemberAddressTransformer? = nil
    public var vtableOffsetTransformer: VTableOffsetTransformer? = nil
    public var fieldOffsetTransformer: FieldOffsetTransformer? = nil
    public var expandedFieldOffsetTransformer: ExpandedFieldOffsetTransformer? = nil
    public var typeLayoutTransformer: TypeLayoutTransformer? = nil
    public var enumLayoutTransformer: EnumLayoutTransformer? = nil
    public var enumLayoutCaseTransformer: EnumLayoutCaseTransformer? = nil
}

// MARK: - Visibility Options

extension SwiftDeclarationPrintConfiguration {
    /// Whether `option` is on in this configuration. `resolvesOpaqueTypes`
    /// answers for `.opaqueTypeResolution`, which is not a setting of the
    /// configuration but whether an opaque type resolver is registered.
    public func isEnabled(_ option: SwiftVisibilityOption, resolvesOpaqueTypes: Bool) -> Bool {
        switch option {
        case .printStrippedSymbolicItem: printStrippedSymbolicItem
        case .printFieldOffset: printFieldOffset
        case .printExpandedFieldOffsets: printExpandedFieldOffsets
        case .printMemberAddress: printMemberAddress
        case .printVTableOffset: printVTableOffset
        case .printPWTOffset: printPWTOffset
        case .printTypeLayout: printTypeLayout
        case .printEnumLayout: printEnumLayout
        case .infersObjCOverridesFromSelectorNames: infersObjCOverridesFromSelectorNames
        case .opaqueTypeResolution: resolvesOpaqueTypes
        }
    }

    /// Whether the option named `optionName` is on — the predicate to project
    /// a marked interface with. A name that is not a `SwiftVisibilityOption`
    /// reads as off.
    public func isVisibilityOptionEnabled(_ optionName: String, resolvesOpaqueTypes: Bool) -> Bool {
        SwiftVisibilityOption(rawValue: optionName).map { isEnabled($0, resolvesOpaqueTypes: resolvesOpaqueTypes) } ?? false
    }
}
