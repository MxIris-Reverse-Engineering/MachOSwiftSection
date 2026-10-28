import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// An `@objc` protocol declared in Swift that the image defines (evolution
/// proposal `swift-declared-objc-protocols`).
///
/// The compiler gives such a protocol no Swift protocol descriptor, so it is
/// no ``ProtocolDefinition``: what the image keeps of it is a
/// `__swift5_fieldmd` record naming it and an Objective-C protocol record
/// holding its requirements — with no Swift symbol for any of them. The
/// requirements are rebuilt from that record by `index(in:)`, each
/// spelled from a Swift class of the image that implements it when there is
/// one, and from its selector by the importer's rules when there is not.
///
/// `@unchecked Sendable` for the reason `TypeDefinition` gives: written only
/// while the model is built and while `index(in:)` runs once behind
/// `DefinitionIndexing`'s lock; printing writes nothing to it.
public final class ObjCProtocolDefinition: @unchecked Sendable {
    /// `Type > Protocol`, the shape a Swift protocol's name takes, so the
    /// image's `extension` of the protocol files under the same
    /// ``ExtensionName``.
    public let protocolName: ProtocolName

    /// The name the Objective-C runtime registers the protocol under; `nil`
    /// when the image holds no record the declaration could be paired with —
    /// the source renamed it with `@objc(Name)` to a name other than its
    /// Swift name.
    public let objcRuntimeName: String?

    /// Whether the source renamed the protocol for the runtime: its runtime
    /// name is not the `_TtP…_` mangling the compiler derives by default.
    public let hasExplicitObjCName: Bool

    /// The protocols it inherits, by Swift name; read by `index(in:)`.
    public package(set) var inheritedProtocolNames: [ProtocolName] = []

    /// The requirements, in the record's order; read by `index(in:)`.
    public package(set) var requirements: [ObjCProtocolRequirementDefinition] = []

    /// The image's `extension`s of the protocol: their members' symbols name
    /// the protocol as an extended context, as for a Swift protocol.
    public package(set) var defaultImplementationExtensions: [ExtensionDefinition] = []

    /// Never a verdict: the protocol has no symbol of its own.
    public let exportStatus: ExportStatus = .declarationHasNoSymbol

    /// Whether `index(in:)` has completed a pass over this definition. Safe
    /// to read from any thread.
    public var isIndexed: Bool {
        DefinitionIndexing.isIndexed(self)
    }

    /// The flag behind `isIndexed`; `DefinitionIndexing` alone reads and
    /// writes it, under its lock.
    var hasCompletedIndexing = false

    /// What the image's index found: the record, and how the protocol was
    /// recognized.
    package let declaredProtocol: SwiftDeclaredObjCProtocol

    package init(declaredProtocol: SwiftDeclaredObjCProtocol, in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        let node = try demangleAsNodeTransient(declaredProtocol.mangledName)
        guard let protocolNode = node.first(of: .protocol) else {
            throw ObjCProtocolDefinitionError.nameIsNoProtocol(mangledName: declaredProtocol.mangledName)
        }
        let typeNode = Node.createTransient(kind: .type, child: protocolNode)
        self.protocolName = ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO))
        self.objcRuntimeName = declaredProtocol.record?.runtimeName
        self.hasExplicitObjCName = declaredProtocol.hasExplicitObjCName
        self.declaredProtocol = declaredProtocol
    }
}

public enum ObjCProtocolDefinitionError: Error, CustomStringConvertible {
    case nameIsNoProtocol(mangledName: String)

    public var description: String {
        switch self {
        case .nameIsNoProtocol(let mangledName): "the name \(mangledName) of an @objc protocol's field descriptor names no protocol"
        }
    }
}

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
    public enum Source: Sendable, Hashable {
        /// The importer's rules applied to the selector and its type
        /// encoding: the Swift name may differ from the source's.
        case selector
        /// The member implementing it in a Swift class of the image that
        /// adopts the protocol, by the class's qualified name: the Swift name
        /// and types are the source's.
        case conformer(className: String)
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
    public let source: Source
    /// Whether the interface spells the selector out (`@objc(selector)`):
    /// always for a requirement named from its selector; for one taken from
    /// a conformer, when the conformer's member spelled it out.
    public let hasExplicitSelector: Bool
    /// The method's type encoding, extended when the record carries one, or
    /// the property's attribute string.
    public let typeEncoding: String

    public var isSettable: Bool {
        setterSelector != nil
    }

    package init(kind: Kind, node: NodeReference, selector: String, setterSelector: String?, isClassMember: Bool, isOptional: Bool, source: Source, hasExplicitSelector: Bool, typeEncoding: String) {
        self.kind = kind
        self.node = node
        self.selector = selector
        self.setterSelector = setterSelector
        self.isClassMember = isClassMember
        self.isOptional = isOptional
        self.source = source
        self.hasExplicitSelector = hasExplicitSelector
        self.typeEncoding = typeEncoding
    }
}
