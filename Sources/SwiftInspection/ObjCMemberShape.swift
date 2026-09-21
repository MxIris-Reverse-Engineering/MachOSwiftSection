import Foundation
@_spi(Internals) import Demangling

/// The shape of a Swift member as far as its ObjC selector is concerned
/// (evolution proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`): base name, argument labels and arity
/// for a method or initializer, the property name for an accessor, the
/// effects (`throws` / `async`) the compiler folds into the selector, plus
/// whether it is type-level and which type declares it.
///
/// Two rule sets read it, and they are NOT the same rules:
///
/// - ``isConsistent(withSelector:isClassMethod:)`` is the Clang IMPORTER's
///   naming applied forward — could this Swift name be what the importer
///   makes of that selector? Lossy by nature (`encode(with:)` came from
///   `encodeWithCoder:`), so it is a GUARD on the thunk-reference join and
///   the whole evidence of the optional name-based inference.
/// - ``defaultSelector()`` / ``isDefaultSelector(_:)`` is the COMPILER's
///   derivation of a Swift-declared `@objc` member's selector from its Swift
///   name (`lib/AST/Decl.cpp`, `AbstractFunctionDecl::getObjCSelector` and
///   `VarDecl::getDefaultObjCSetterSelector`), deterministic and exact. A
///   method-table selector that differs from it was spelled in `@objc(name)`.
public struct ObjCMemberShape: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// `labels` has one entry per parameter, `nil` for an unlabelled one;
        /// it may be EMPTY for an all-unlabelled member, since the demangler
        /// elides the label list then — which is why `arity` is separate.
        case method(baseName: String, labels: [String?], arity: Int)
        case initializer(labels: [String?], arity: Int)
        case getter(propertyName: String)
        case setter(propertyName: String)
        /// A subscript's accessors answer to fixed selectors
        /// (`objectAtIndexedSubscript:` / `objectForKeyedSubscript:` and the
        /// `setObject:…` pair); which of the two depends on the index type.
        case subscriptGetter
        case subscriptSetter
    }

    public let kind: Kind
    /// Type-level (`static` / `class`) — an ObjC class method.
    public let isStatic: Bool
    /// The declaring type's qualified name: `__C.NSGlassEffectView` for a
    /// member of an extension of an imported class, `SwiftUI.Foo` for a
    /// Swift class's member.
    public let ownerQualifiedName: String?
    /// `throws` (an `error:` selector piece) — irrelevant to accessors.
    public let isThrowing: Bool
    /// `async` (a `completionHandler:` selector piece) — irrelevant to accessors.
    public let isAsync: Bool

    public init(kind: Kind, isStatic: Bool, ownerQualifiedName: String?, isThrowing: Bool = false, isAsync: Bool = false) {
        self.kind = kind
        self.isStatic = isStatic
        self.ownerQualifiedName = ownerQualifiedName
        self.isThrowing = isThrowing
        self.isAsync = isAsync
    }

    /// The shape of a demangled symbol (`global → [attribute…] → [static] →
    /// [getter | setter] → function | allocator | constructor | variable |
    /// subscript`), or `nil` for any other symbol (a type metadata accessor,
    /// a witness, a modify accessor — nothing an ObjC method entry point
    /// could be). A `To` thunk symbol demangles to the same entity behind an
    /// `objCAttribute` child, which is skipped.
    public init?(demangledSymbol root: Node) {
        var node = root
        if node.kind == .global {
            // `mergedFunction` / `asyncFunctionPointer` wrappers and the thunk
            // attributes (`objCAttribute`, `dynamicAttribute`, …) sit beside
            // the entity; the entity is the child that is none of those.
            guard let entity = node.children.first(where: { !Self.isWrapperOrAttribute($0.kind) }) else { return nil }
            node = entity
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
            case .function, .allocator, .constructor, .variable, .subscript:
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
        case .subscript:
            switch accessorKind {
            case .getter: self.init(kind: .subscriptGetter, isStatic: isStatic, ownerQualifiedName: ownerQualifiedName)
            case .setter: self.init(kind: .subscriptSetter, isStatic: isStatic, ownerQualifiedName: ownerQualifiedName)
            default: return nil
            }
        case .function:
            guard accessorKind == nil, let baseName = Self.declaredName(of: node), let arity = Self.arity(of: node) else { return nil }
            let effects = Self.effects(of: node)
            self.init(kind: .method(baseName: baseName, labels: Self.labels(of: node), arity: arity), isStatic: isStatic, ownerQualifiedName: ownerQualifiedName, isThrowing: effects.isThrowing, isAsync: effects.isAsync)
        case .allocator, .constructor:
            guard accessorKind == nil, let arity = Self.arity(of: node) else { return nil }
            let effects = Self.effects(of: node)
            self.init(kind: .initializer(labels: Self.labels(of: node), arity: arity), isStatic: false, ownerQualifiedName: ownerQualifiedName, isThrowing: effects.isThrowing, isAsync: effects.isAsync)
        default:
            return nil
        }
    }

    private static func isWrapperOrAttribute(_ kind: Node.Kind) -> Bool {
        switch kind {
        case .mergedFunction, .asyncFunctionPointer, .objCAttribute, .nonObjCAttribute, .dynamicAttribute, .directMethodReferenceAttribute:
            true
        default:
            false
        }
    }

    // MARK: - Selector consistency (the importer's rules, forward)

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
    ///   (`initWithCoder:` ↔ `init(coder:)`);
    /// - a subscript accessor: one of the runtime's four fixed selectors.
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
        case .subscriptGetter:
            return Self.subscriptGetterSelectors.contains(selector)
        case .subscriptSetter:
            return Self.subscriptSetterSelectors.contains(selector)
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

    // MARK: - Default selector (the compiler's derivation)

    /// The selector the compiler gives a Swift-declared `@objc` member with
    /// this shape and no `@objc(name)` — `AbstractFunctionDecl::getObjCSelector`
    /// ported rule by rule:
    ///
    /// - no parameters: the base name (`layout`); one unlabelled parameter:
    ///   `baseName:` (`addSubview:`);
    /// - otherwise the first piece is the base name, then — when the first
    ///   parameter has a label — `With` unless that label's first word or
    ///   the base name's last word is a preposition, then the capitalized
    ///   label (`viewWillMove(toWindow:)` → `viewWillMoveToWindow:`,
    ///   `perform(after:)` → `performAfter:`, `move(to:)` → `moveTo:`);
    ///   every later piece is its label verbatim, empty for `_`;
    /// - `throws` appends an `error:` piece (`fetchAndReturnError:` when it
    ///   is the only one); `async` appends `completionHandler:`
    ///   (`loadWithCompletionHandler:` when it is the only one); `async
    ///   throws` appends only the completion handler;
    /// - an initializer is a method whose base name is `init`
    ///   (`init(coder:)` → `initWithCoder:`, `init()` → `init`);
    /// - a getter is the property name, a setter `set` + the capitalized
    ///   property name — NO `is` handling, that is an importer rule
    ///   (`isEnabled` → `setIsEnabled:`).
    ///
    /// `nil` for a subscript accessor, whose selector depends on the index
    /// type; ``isDefaultSelector(_:)`` accepts the runtime's four spellings.
    public func defaultSelector() -> String? {
        switch kind {
        case .getter(let propertyName):
            return propertyName
        case .setter(let propertyName):
            return "set" + Self.capitalizingFirst(propertyName) + ":"
        case .subscriptGetter, .subscriptSetter:
            return nil
        case .method(let baseName, let labels, let arity):
            return Self.derivedSelector(baseName: baseName, labels: labels, arity: arity, isThrowing: isThrowing, isAsync: isAsync)
        case .initializer(let labels, let arity):
            return Self.derivedSelector(baseName: "init", labels: labels, arity: arity, isThrowing: isThrowing, isAsync: isAsync)
        }
    }

    /// Whether `selector` is what the compiler would derive — the negation
    /// is "the source wrote `@objc(name)`".
    public func isDefaultSelector(_ selector: String) -> Bool {
        switch kind {
        case .subscriptGetter: Self.subscriptGetterSelectors.contains(selector)
        case .subscriptSetter: Self.subscriptSetterSelectors.contains(selector)
        default: defaultSelector() == selector
        }
    }

    static let subscriptGetterSelectors: Set<String> = ["objectAtIndexedSubscript:", "objectForKeyedSubscript:"]
    static let subscriptSetterSelectors: Set<String> = ["setObject:atIndexedSubscript:", "setObject:forKeyedSubscript:"]

    private static func derivedSelector(baseName: String, labels: [String?], arity: Int, isThrowing: Bool, isAsync: Bool) -> String {
        // A completion handler subsumes the error; a thrown error alone
        // becomes a trailing `error:` parameter.
        let appendsCompletionHandler = isAsync
        let appendsError = isThrowing && !isAsync
        let pieceCount = arity + (appendsCompletionHandler ? 1 : 0) + (appendsError ? 1 : 0)
        if pieceCount == 0 { return baseName }
        func label(_ index: Int) -> String? {
            guard index < labels.count, let label = labels[index], label != "_", !label.isEmpty else { return nil }
            return label
        }
        if pieceCount == 1, arity == 1, label(0) == nil { return baseName + ":" }

        var pieces: [String] = []
        var argumentIndex = 0
        for pieceIndex in 0 ..< pieceCount {
            if pieceIndex > 0 {
                if pieceIndex == arity {
                    // The convention's inserted parameter comes after the
                    // declared ones.
                    pieces.append(appendsCompletionHandler ? "completionHandler" : "error")
                    continue
                }
                pieces.append(label(argumentIndex) ?? "")
                argumentIndex += 1
                continue
            }
            var firstPiece = baseName
            if arity == 0 {
                firstPiece += appendsCompletionHandler ? "WithCompletionHandler" : "AndReturnError"
            } else if let firstLabel = label(0) {
                if !isPreposition(CamelCaseWords.firstWord(of: firstLabel)), !isPreposition(CamelCaseWords.lastWord(of: baseName)) {
                    firstPiece += "With"
                }
                firstPiece += capitalizingFirst(firstLabel)
                argumentIndex = 1
            } else {
                argumentIndex = 1
            }
            pieces.append(firstPiece)
        }
        return pieces.joined(separator: ":") + ":"
    }

    /// The compiler's preposition list (`lib/Basic/PartsOfSpeech.def`), the
    /// words that suppress the `With` between a base name and a first label.
    package static let prepositions: Set<String> = [
        "above", "after", "along", "alongside", "as", "at", "before", "below", "by", "following", "for", "from",
        "given", "in", "including", "inside", "into", "matching", "of", "on", "passing", "preceding", "since",
        "to", "until", "using", "via", "when", "with", "within",
    ]

    private static func isPreposition(_ word: String) -> Bool {
        prepositions.contains(word.lowercased())
    }

    /// `camel_case::Words` — an identifier split at its capitalization
    /// boundaries, an all-caps run kept together as one acronym word
    /// (`URLSession` → `URL`, `Session`).
    package enum CamelCaseWords {
        package static func words(of identifier: String) -> [String] {
            let scalars = Array(identifier.unicodeScalars)
            guard !scalars.isEmpty else { return [] }
            var words: [String] = []
            var start = 0
            var index = 1
            func isUpper(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isUppercase }
            func isLower(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isLowercase }
            while index < scalars.count {
                let current = scalars[index]
                let previous = scalars[index - 1]
                var startsWord = false
                if isUpper(current) {
                    if !isUpper(previous) {
                        // `viewWill|Move`
                        startsWord = true
                    } else if index + 1 < scalars.count, isLower(scalars[index + 1]) {
                        // `URL|Session`: the last capital of a run begins the
                        // next word when a lowercase letter follows it.
                        startsWord = true
                    }
                } else if current == "_" {
                    startsWord = true
                }
                if startsWord {
                    words.append(String(String.UnicodeScalarView(scalars[start ..< index])))
                    start = index
                }
                index += 1
            }
            words.append(String(String.UnicodeScalarView(scalars[start...])))
            return words.filter { !$0.isEmpty && $0 != "_" }
        }

        package static func firstWord(of identifier: String) -> String {
            words(of: identifier).first ?? identifier
        }

        package static func lastWord(of identifier: String) -> String {
            words(of: identifier).last ?? identifier
        }
    }

    // MARK: - String helpers

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

    private static func functionType(of node: Node) -> Node? {
        guard let typeNode = node.children.last(where: { $0.kind == .type }) else { return nil }
        return typeNode.children.first(where: { $0.kind == .functionType || $0.kind == .noEscapeFunctionType })
    }

    /// The parameter count from the function type: the argument tuple's
    /// element count, one for a single unlabelled parameter, zero for `()`.
    private static func arity(of node: Node) -> Int? {
        guard let functionType = functionType(of: node),
              let argumentTuple = functionType.children.first(where: { $0.kind == .argumentTuple }),
              let argumentType = argumentTuple.children.first(where: { $0.kind == .type }),
              let argument = argumentType.children.first
        else { return nil }
        if argument.kind == .tuple {
            return argument.children.count
        }
        return 1
    }

    /// `throws` / `async` from the function type's annotation children.
    private static func effects(of node: Node) -> (isThrowing: Bool, isAsync: Bool) {
        guard let functionType = functionType(of: node) else { return (false, false) }
        let isThrowing = functionType.children.contains { $0.kind == .throwsAnnotation || $0.kind == .typedThrowsAnnotation }
        let isAsync = functionType.children.contains { $0.kind == .asyncAnnotation }
        return (isThrowing, isAsync)
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
