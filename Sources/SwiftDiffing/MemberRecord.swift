import Demangling
import SwiftDeclaration

/// A diff-ready projection of one member.
///
/// Two keys drive the algorithm:
/// - `identityKey` matches members across the two sides (added / removed /
///   common). For symbol-backed members it is the remangled declaration node
///   (the ABI identity); for entities with no symbol (stored fields, enum
///   cases, deinit) it is a namespaced source name, so a rename is add+remove.
/// - `payloadKey` detects a change *among matched* members. It folds in every
///   ABI-significant attribute that the identity does not already encode — for
///   a variable/subscript that is the accessor set (so `let` → `var` reports
///   `.modified`), for a field it is the type, for an enum case it is the tag
///   (so reordering / mid-inserting a case reports `.modified`).
public struct MemberRecord: Sendable, Codable, Equatable {
    public let identityKey: ABIKey
    public let payloadKey: ABIKey
    public let kind: MemberKind
    /// Human-readable rendering, surfaced on `MemberChange`.
    public let signature: String

    public init(identityKey: ABIKey, payloadKey: ABIKey, kind: MemberKind, signature: String) {
        self.identityKey = identityKey
        self.payloadKey = payloadKey
        self.kind = kind
        self.signature = signature
    }
}

// MARK: - Projection from the declaration model

extension MemberRecord {
    /// A function's mangled declaration node encodes static-ness and the
    /// function flavor (allocator / init), so for functions the node is both
    /// identity and payload — a matched function symbol is, by construction,
    /// unchanged.
    public static func make(_ function: FunctionDefinition) -> MemberRecord {
        let key = ABIKey.make(for: function.node)
        let kind: MemberKind
        switch function.kind {
        case .function: kind = .function
        case .allocator: kind = .allocator
        case .constructor: kind = .constructor
        }
        return MemberRecord(
            identityKey: key,
            payloadKey: key,
            kind: kind,
            signature: function.node.print(using: .default)
        )
    }

    /// `DefinitionBuilder` picks the *getter* node as `.node`, so the identity
    /// tracks the property's type but NOT its mutability — a `let` → `var`
    /// change adds a separate setter symbol while leaving the getter identical.
    /// We therefore fold the accessor set into the payload so a mutability
    /// change reports `.modified`.
    public static func make(_ variable: VariableDefinition) -> MemberRecord {
        let identity = ABIKey.make(for: variable.node)
        return MemberRecord(
            identityKey: identity,
            payloadKey: composedPayload(identity, accessorTag(variable.accessors)),
            kind: .variable,
            signature: variable.node.print(using: .default)
        )
    }

    /// Same accessor caveat as `make(_ variable:)`.
    public static func make(_ subscriptDefinition: SubscriptDefinition) -> MemberRecord {
        let identity = ABIKey.make(for: subscriptDefinition.node)
        return MemberRecord(
            identityKey: identity,
            payloadKey: composedPayload(identity, accessorTag(subscriptDefinition.accessors)),
            kind: .subscript,
            signature: subscriptDefinition.node.print(using: .default)
        )
    }

    /// A stored field has no declaration symbol. Its identity is its source
    /// name (kept in a distinct `"field:"` namespace so it cannot collide with
    /// a same-spelled method's mangled key); its payload is its (unwrapped)
    /// type, so a retype at the same name is a `.modified`.
    ///
    /// Field *order* is deliberately not folded in here: for a resilient
    /// (non-frozen) struct, reordering stored properties is binary-compatible,
    /// so order-sensitivity would be a false positive. Enum cases — where order
    /// IS unconditionally ABI-significant — use ``makeCase(_:tag:)`` instead.
    /// TODO(P2): resilience-aware frozen-struct field-order sensitivity; fold
    /// `flags` (weak / lazy / indirect) into `payloadKey`.
    public static func make(_ field: FieldDefinition) -> MemberRecord {
        let typeText = field.typeNode.print(using: .default)
        return MemberRecord(
            identityKey: .printed("field:" + field.name),
            payloadKey: ABIKey.makeUnwrappingType(for: field.typeNode),
            kind: .field,
            signature: field.name + ": " + typeText
        )
    }

    /// An enum case, keyed by name with the discriminant `tag` (declaration
    /// order) folded into the payload. Reordering or mid-inserting a case
    /// renumbers tags, which is unconditionally an ABI break, so the affected
    /// cases report `.modified`; appending a case leaves existing tags intact
    /// and only the new case reports `.added`.
    public static func makeCase(_ field: FieldDefinition, tag: Int) -> MemberRecord {
        let payloadText = field.typeNode.print(using: .default)
        return MemberRecord(
            identityKey: .printed("case:" + field.name),
            payloadKey: .printed("tag:\(tag)|" + payloadText),
            kind: .enumCase,
            signature: "case " + field.name
        )
    }

    /// The presence of a deallocator (`deinit`) is itself an ABI signal — a
    /// class gaining `__deallocating_deinit`, or a value type becoming
    /// `~Copyable`, adds the slot. Keyed on presence only.
    public static func makeDeinit() -> MemberRecord {
        MemberRecord(identityKey: .printed("deinit"), payloadKey: .printed("deinit"), kind: .deinit, signature: "deinit")
    }

    /// A protocol's associated-type requirement (`ProtocolDefinition
    /// .associatedTypes` is `[String]`). Adding / removing one changes the
    /// protocol's witness-table shape, so it is an ABI signal. Keyed by name in
    /// its own namespace, so a rename is add+remove.
    public static func makeAssociatedType(_ name: String) -> MemberRecord {
        MemberRecord(
            identityKey: .printed("associatedType:" + name),
            payloadKey: .printed("associatedType:" + name),
            kind: .associatedType,
            signature: "associatedtype " + name
        )
    }

    /// A stable, order-independent fingerprint of a member's accessor kinds.
    private static func accessorTag(_ accessors: [Accessor]) -> String {
        accessors.map { accessorKindToken($0.kind) }.sorted().joined(separator: ",")
    }

    /// Stable token per accessor kind — an explicit switch rather than
    /// `String(describing:)` reflection, so the payload key stays injective by
    /// code rather than by the compiler's enum description format.
    static func accessorKindToken(_ kind: AccessorKind) -> String {
        switch kind {
        case .getter: return "get"
        case .setter: return "set"
        case .modifyAccessor: return "modify"
        case .readAccessor: return "read"
        case .none: return "none"
        }
    }

    /// Combine an identity key with an extra attribute string into a payload
    /// key that differs whenever either component differs.
    private static func composedPayload(_ identity: ABIKey, _ attribute: String) -> ABIKey {
        .printed(identity.sortKey + "|acc:" + attribute)
    }
}
