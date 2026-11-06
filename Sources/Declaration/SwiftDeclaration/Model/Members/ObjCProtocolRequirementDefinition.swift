import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// One requirement of an ``ObjCProtocolDefinition``: a Swift declaration
/// built from the protocol's Objective-C record, shaped like the member
/// symbol the compiler would have demangled to.
public struct ObjCProtocolRequirementDefinition: Sendable {
    public enum Kind: Sendable, Hashable {
        case method
        case initializer
        case property
        case `subscript`
    }

    /// Where the Swift spelling comes from.
    public enum Origin: Sendable, Hashable {
        /// The importer's rules applied to the selector and its type
        /// encoding: the Swift name may differ from the source's.
        case selector
        /// The member implementing it in a class of the image that adopts
        /// the protocol — a Swift class, or an Objective-C class the image
        /// extends in a category: the Swift name and types are the source's.
        case conformer(className: TypeName)
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
    public let isOptional: Bool
    public let origin: Origin
    /// Whether the interface spells the selector out (`@objc(selector)`):
    /// always for a requirement named from its selector; for one taken from
    /// a conformer, when the compiler derives another selector from the
    /// member's Swift name.
    public let hasExplicitSelector: Bool
    /// The method's type encoding, extended when the record carries one, or
    /// the property's attribute string.
    public let typeEncoding: String

    public var isSettable: Bool {
        setterSelector != nil
    }

    @available(*, deprecated, renamed: "Origin")
    public typealias Source = Origin

    @available(*, deprecated, renamed: "origin")
    public var source: Origin {
        origin
    }

    package init(kind: Kind, node: NodeReference, selector: String, setterSelector: String?, isClassMember: Bool, isOptional: Bool, origin: Origin, hasExplicitSelector: Bool, typeEncoding: String) {
        self.kind = kind
        self.node = node
        self.selector = selector
        self.setterSelector = setterSelector
        self.isClassMember = isClassMember
        self.isOptional = isOptional
        self.origin = origin
        self.hasExplicitSelector = hasExplicitSelector
        self.typeEncoding = typeEncoding
    }
}
