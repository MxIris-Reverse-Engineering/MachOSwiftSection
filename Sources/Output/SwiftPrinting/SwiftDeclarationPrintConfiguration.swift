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

/// Where the interface writes a protocol requirement about one of the
/// protocol's own associated types (evolution proposal
/// `protocol-requirement-placement`).
///
/// The binary records only the canonical requirement signature, never where
/// the source wrote a requirement, and the two placements state exactly the
/// same requirements: each one once, in the same words, only somewhere else.
/// A requirement on `Self` itself — a refined protocol, `AnyObject`, a
/// superclass — stays in the protocol's inheritance clause under both.
public enum ProtocolRequirementPlacement: Hashable, Codable, Sendable, CaseIterable {
    /// Every requirement in the protocol's `where` clause:
    ///
    /// ```swift
    /// protocol Menu where Self.Item: Swift.Sequence, Self.Item.Element: Swift.Hashable {
    ///     associatedtype Item
    /// }
    /// ```
    case protocolWhereClause

    /// Each requirement on the associated type it is about, the way the
    /// compiler writes a `.swiftinterface`:
    ///
    /// ```swift
    /// protocol Menu {
    ///     associatedtype Item: Swift.Sequence where Self.Item.Element: Swift.Hashable
    /// }
    /// ```
    ///
    /// A conformance, superclass or layout requirement goes by its subject
    /// alone: on exactly `Self.Item` into `Item`'s inheritance clause, on a
    /// member chain starting from `Item` (`Self.Item.Element`) into `Item`'s
    /// `where` clause, as written in the protocol's. One whose subject is not
    /// about the protocol's own associated types stays in the protocol's
    /// `where` clause, even when its superclass names one
    /// (`Self.Element: Base<Self.Item>` on a `Sequence` refinement). A
    /// same-type requirement goes into the `where` clause of an associated
    /// type either side is about, a side that is exactly `Self.Item` first.
    /// Inverse and same-shape requirements stay in the protocol's `where`
    /// clause.
    case associatedTypes
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
    /// members, a C-imported type) is kept, so the filter never drops on a
    /// guess.
    ///
    /// A marked print (`marksOptionalContent`) leaves nothing out for it: it
    /// prints what the filter rules out in a region visible only while this
    /// is off (evolution proposal `exported-only-marking-mode`).
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

    /// Qualify names with SE-0491 module selectors — `Swift::Int` instead of
    /// `Swift.Int` — as the Swift 6.4 compiler does when it writes a
    /// `.swiftinterface` (evolution proposal `module-selectors`). Every type
    /// level carries the module that declared it, so a type another module
    /// adds in an extension says where it comes from
    /// (`Swift::Duration.Foundation::TimeFormatStyle`); a local type and the
    /// associated type of a type parameter (`A.Element`) carry none.
    ///
    /// Off by default, and off the output is unchanged byte for byte.
    public var usesModuleSelectors: Bool = false

    /// Where a requirement about one of a protocol's own associated types
    /// prints: in the protocol's `where` clause (the default, unchanged byte
    /// for byte), or on that `associatedtype` (evolution proposal
    /// `protocol-requirement-placement`). The requirements are the same
    /// either way.
    ///
    /// The diff and evolution interfaces always print `.protocolWhereClause`:
    /// they compare a protocol's `associatedtype` lines by name alone and
    /// print no requirement on them.
    public var protocolRequirementPlacement: ProtocolRequirementPlacement = .protocolWhereClause

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
    /// order, the `// not exported` annotation (`printExportStatus`) —
    /// applies as usual.
    ///
    /// For the opaque type constraints to be there to mark, register the
    /// opaque type resolver as for a normal print. For the exported-only
    /// filter to rule on extensions, install the export filter scope
    /// (`SwiftDeclarationPrinter.installExportFilterScope(types:protocols:)`)
    /// as for a normal print with the filter on — `SwiftInterfaceBuilder`'s
    /// `printRoot()` installs it for a marked print too.
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
    /// One exception with `marksOptionalContent`: a definition the
    /// exported-only filter keeps inside one it rules out — an exported type
    /// nested in an unexported one, which an OS framework's export list
    /// allows (Foundation's `LocalePreferences.ICUSymbolsAndStrings`). The
    /// parent's print marks all of the parent, the child included, as
    /// visible only while `printExportedDeclarationsOnly` is off, so the
    /// region reads as the child's own print with the filter off and is gone
    /// with it on, where the child's own print stays (evolution proposal
    /// `exported-only-marking-mode`). The host prints such a child on its
    /// own: one whose own `exportStatus` is not `isDefinitelyNotExported`
    /// while an enclosing definition's is.
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
        case .printExportedDeclarationsOnly: printExportedDeclarationsOnly
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
