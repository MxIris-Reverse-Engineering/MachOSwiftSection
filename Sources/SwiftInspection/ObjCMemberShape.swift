import Foundation
@_spi(Internals) import Demangling

/// The shape of a Swift member as far as its ObjC selector is concerned
/// (evolution proposal `objc-ancestor-override-recovery`): base name,
/// argument labels and arity for a method or initializer, the property name
/// for an accessor, plus whether it is type-level and which type declares it.
///
/// Used as the GUARD on the thunk-reference join — a stripped thunk's code
/// may reference other members of the class (an inlined body calling
/// `self.update()`), and only the member whose name is the importer's
/// spelling of the selector may be tied to it — and as the whole evidence
/// of the optional name-based inference.
public struct ObjCMemberShape: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// `labels` has one entry per parameter, `nil` for an unlabelled one;
        /// it may be EMPTY for an all-unlabelled member, since the demangler
        /// elides the label list then — which is why `arity` is separate.
        case method(baseName: String, labels: [String?], arity: Int)
        case initializer(labels: [String?], arity: Int)
        case getter(propertyName: String)
        case setter(propertyName: String)
    }

    public let kind: Kind
    /// Type-level (`static` / `class`) — an ObjC class method.
    public let isStatic: Bool
    /// The declaring type's qualified name: `__C.NSGlassEffectView` for a
    /// member of an extension of an imported class, `SwiftUI.Foo` for a
    /// Swift class's member.
    public let ownerQualifiedName: String?

    public init(kind: Kind, isStatic: Bool, ownerQualifiedName: String?) {
        self.kind = kind
        self.isStatic = isStatic
        self.ownerQualifiedName = ownerQualifiedName
    }

    /// The shape of a demangled symbol (`global → [static] → [getter | setter]
    /// → function | allocator | constructor | variable`), or `nil` for any
    /// other symbol (a type metadata accessor, a witness, a modify accessor —
    /// nothing an ObjC method entry point could be).
    public init?(demangledSymbol root: Node) {
        var node = root
        if node.kind == .global {
            guard let entity = node.children.first else { return nil }
            node = entity
            // `mergedFunction` / `asyncFunctionPointer` wrappers put the
            // entity second.
            if node.kind == .mergedFunction || node.kind == .asyncFunctionPointer, let second = root.children.dropFirst().first {
                node = second
            }
        }
        var isStatic = false
        var accessorKind: Node.Kind?
        var depth = 0
        while depth < 4 {
            depth += 1
            switch node.kind {
            case .static:
                isStatic = true
            case .getter, .setter:
                accessorKind = node.kind
            case .function, .allocator, .constructor, .variable:
                depth = 4
                continue
            default:
                return nil
            }
            guard let next = node.children.first else { return nil }
            node = next
        }
        let ownerQualifiedName = node.children.first.flatMap(Self.ownerQualifiedName(ofContext:))
        switch node.kind {
        case .variable:
            guard let propertyName = Self.declaredName(of: node) else { return nil }
            switch accessorKind {
            case .getter: self.init(kind: .getter(propertyName: propertyName), isStatic: isStatic, ownerQualifiedName: ownerQualifiedName)
            case .setter: self.init(kind: .setter(propertyName: propertyName), isStatic: isStatic, ownerQualifiedName: ownerQualifiedName)
            default: return nil
            }
        case .function:
            guard accessorKind == nil, let baseName = Self.declaredName(of: node), let arity = Self.arity(of: node) else { return nil }
            self.init(kind: .method(baseName: baseName, labels: Self.labels(of: node), arity: arity), isStatic: isStatic, ownerQualifiedName: ownerQualifiedName)
        case .allocator, .constructor:
            guard accessorKind == nil, let arity = Self.arity(of: node) else { return nil }
            self.init(kind: .initializer(labels: Self.labels(of: node), arity: arity), isStatic: false, ownerQualifiedName: ownerQualifiedName)
        default:
            return nil
        }
    }

    // MARK: - Selector consistency

    /// Whether `selector` is a spelling the Clang importer would turn into
    /// this member's name — the forward direction of the importer's rules,
    /// applied as a check rather than a derivation:
    ///
    /// - a zero-argument method or a getter: the selector IS the name
    ///   (`layout` ↔ `layout()`, `clipsToBounds` ↔ `clipsToBounds`);
    /// - a setter: `set` + the capitalized property name, an `is` prefix
    ///   dropped (`setClipsToBounds:`, `setEnabled:` ↔ `isEnabled`);
    /// - an n-argument method: n selector pieces; the first begins with the
    ///   base name and what follows it, lowercased, begins with the first
    ///   label (`viewWillMoveToWindow:` ↔ `viewWillMove(toWindow:)`,
    ///   `encodeWithCoder:` ↔ `encode(with:)`); every later piece,
    ///   lowercased, begins with its label (`replacementRange:`,
    ///   `withObject:` ↔ `with:`); an unlabelled parameter accepts anything;
    /// - an initializer: `init` + the same, with a leading `With` skipped
    ///   (`initWithCoder:` ↔ `init(coder:)`).
    ///
    /// A member renamed through APINotes or `@objc(name)` fails the check and
    /// is simply not attributed — a miss, never a wrong attribution.
    public func isConsistent(withSelector selector: String, isClassMethod: Bool) -> Bool {
        guard isClassMethod == isStatic else { return false }
        let pieces = Self.pieces(ofSelector: selector)
        let argumentCount = selector.filter { $0 == ":" }.count
        switch kind {
        case .getter(let propertyName):
            return argumentCount == 0 && selector == propertyName
        case .setter(let propertyName):
            guard argumentCount == 1, let piece = pieces.first, piece.hasPrefix("set") else { return false }
            let setterCore = String(piece.dropFirst(3))
            if setterCore == Self.capitalizingFirst(propertyName) { return true }
            if propertyName.count > 2, propertyName.hasPrefix("is"), setterCore == String(propertyName.dropFirst(2)) { return true }
            return false
        case .method(let baseName, let labels, let arity):
            guard argumentCount == arity else { return false }
            if arity == 0 { return selector == baseName }
            return Self.piecesMatch(pieces, baseName: baseName, labels: labels, arity: arity, skippingLeadingWith: false)
        case .initializer(let labels, let arity):
            guard !isClassMethod, argumentCount == arity else { return false }
            if arity == 0 { return selector == "init" }
            return Self.piecesMatch(pieces, baseName: "init", labels: labels, arity: arity, skippingLeadingWith: true)
        }
    }

    private static func piecesMatch(_ pieces: [String], baseName: String, labels: [String?], arity: Int, skippingLeadingWith: Bool) -> Bool {
        guard pieces.count == arity, let firstPiece = pieces.first, firstPiece.hasPrefix(baseName) else { return false }
        for index in 0 ..< arity {
            let label: String? = index < labels.count ? labels[index] : nil
            guard let label, label != "_" else { continue }
            var piece = pieces[index]
            if index == 0 {
                piece = String(piece.dropFirst(baseName.count))
                if skippingLeadingWith, piece.hasPrefix("With") {
                    piece = String(piece.dropFirst(4))
                }
            }
            guard lowercasingFirst(piece).hasPrefix(label) else { return false }
        }
        return true
    }

    private static func pieces(ofSelector selector: String) -> [String] {
        guard selector.hasSuffix(":") else { return [selector] }
        return selector.dropLast().split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    }

    private static func lowercasingFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.lowercased() + string.dropFirst()
    }

    private static func capitalizingFirst(_ string: String) -> String {
        guard let first = string.first else { return string }
        return first.uppercased() + string.dropFirst()
    }

    // MARK: - Node reading

    private static func declaredName(of node: Node) -> String? {
        node.children.first { $0.kind == .identifier }?.text
    }

    private static func labels(of node: Node) -> [String?] {
        guard let list = node.children.first(where: { $0.kind == .labelList }) else { return [] }
        return list.children.map { child in
            child.kind == .firstElementMarker ? nil : child.text
        }
    }

    /// The parameter count from the function type: the argument tuple's
    /// element count, one for a single unlabelled parameter, zero for `()`.
    private static func arity(of node: Node) -> Int? {
        guard let typeNode = node.children.last(where: { $0.kind == .type }),
              let functionType = typeNode.children.first(where: { $0.kind == .functionType || $0.kind == .noEscapeFunctionType }),
              let argumentTuple = functionType.children.first(where: { $0.kind == .argumentTuple }),
              let argumentType = argumentTuple.children.first(where: { $0.kind == .type }),
              let argument = argumentType.children.first
        else { return nil }
        if argument.kind == .tuple {
            return argument.children.count
        }
        return 1
    }

    private static func ownerQualifiedName(ofContext context: Node) -> String? {
        switch context.kind {
        case .extension:
            // `.extension` children are [module, extendedType, ...].
            return context.children.dropFirst().first.flatMap { NodeTypeNaming.nominalQualifiedName(of: $0) }
        default:
            return NodeTypeNaming.nominalQualifiedName(of: context)
        }
    }
}
