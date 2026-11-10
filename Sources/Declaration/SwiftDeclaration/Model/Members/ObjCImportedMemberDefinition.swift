import Foundation
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

/// One member of an Objective-C class or category as Swift imports it
/// (evolution proposal `objc-imported-declarations`): a Swift declaration
/// built from the method and property lists by the importer's rules, shaped
/// like the member symbol the compiler would have demangled to. Its Swift
/// name may not be the one the SDK gives it, which only API notes,
/// `NS_SWIFT_NAME` and the header's types decide; the interface pins the
/// selector with `@objc(selector)` where the compiler would derive another
/// from the printed name.
public struct ObjCImportedMemberDefinition: Sendable {
    public enum Kind: Sendable, Hashable {
        case method
        case initializer
        /// A class method restating its class's name, which the importer
        /// imports as a convenience initializer.
        case factoryInitializer
        case property
        case `subscript`
    }

    /// How an object property holds its value, from its attributes.
    public enum Ownership: Sendable, Hashable {
        case strong
        /// `copy`: `@NSCopying`.
        case copy
        case weak
        /// `assign` or `unsafe_unretained` on an object: `unowned(unsafe)`.
        case unownedUnsafe
    }

    public let kind: Kind
    /// `Global > Function`, `Global > Static > Getter > Variable`,
    /// `Global > Allocator`, `Global > Getter > Subscript`.
    public let node: NodeReference
    /// The selector the runtime sends: a method's, a property's or a
    /// subscript's getter.
    public let selector: String
    /// A property's or subscript's setter; `nil` when it is read-only.
    public let setterSelector: String?
    public let isClassMember: Bool
    /// An object property's ownership; `nil` for every other member.
    public let ownership: Ownership?
    /// Whether the interface spells the selector out (`@objc(selector)`):
    /// the compiler would derive another one from the printed Swift name.
    public let hasExplicitSelector: Bool
    /// The encoding the declaration was built from: the method list's, an
    /// adopted protocol's extended one, or the property's attributes.
    public let typeEncoding: String

    public var isSettable: Bool {
        setterSelector != nil
    }

    package init(kind: Kind, node: NodeReference, selector: String, setterSelector: String?, isClassMember: Bool, ownership: Ownership?, hasExplicitSelector: Bool, typeEncoding: String) {
        self.kind = kind
        self.node = node
        self.selector = selector
        self.setterSelector = setterSelector
        self.isClassMember = isClassMember
        self.ownership = ownership
        self.hasExplicitSelector = hasExplicitSelector
        self.typeEncoding = typeEncoding
    }
}
