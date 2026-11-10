import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

/// An Objective-C class of the image as Swift imports it (evolution proposal
/// `objc-imported-declarations`): `class Name: Superclass, Protocol… { … }`,
/// its members built from the class's method and property lists by the
/// importer's rules (``ObjCImportedMemberDefinition``).
///
/// When Swift implements the class, the interface prints Swift's own
/// declarations rather than the names the rules derive: a Swift class
/// registered with the runtime prints as the Swift class it is
/// (``swiftClassDefinition``) with its extensions, and a class declared in
/// Objective-C takes each member Swift implements from the image's Swift
/// extension implementing it (``swiftExtensions``). The linker merges the
/// category an extension with `@objc` members compiles to into the class's
/// own lists when the class is the image's, so those members are the class's
/// methods too. The printer pairs them by selector, through the Objective-C
/// member table of those definitions; a member none of them implements still
/// prints by the rules.
///
/// `@unchecked Sendable` for the reason `TypeDefinition` gives: written only
/// while the model is built and while `index(in:)` runs once behind
/// `DefinitionIndexing`'s lock; printing writes nothing to it.
public final class ObjCImportedClassDefinition: @unchecked Sendable {
    /// `Type > Class`: `__C.NSView` for a class declared in Objective-C, a
    /// Swift class under its own name.
    public let className: TypeName

    /// The name the Objective-C runtime registers the class under.
    public let objcRuntimeName: String

    /// Whether the class data's Swift bit is set: a Swift class registered
    /// with the Objective-C runtime.
    public let isSwiftClass: Bool

    /// The Swift class's own definition, for a Swift class this image
    /// indexes; `nil` otherwise.
    public let swiftClassDefinition: TypeDefinition?

    /// The image's Swift extensions of the class: of a Swift class, its
    /// extensions and conformances; of a class declared in Objective-C, its
    /// `@objc @implementation` bodies and the extensions adding `@objc`
    /// members.
    public let swiftExtensions: [ExtensionDefinition]

    /// The superclass, by the name Swift gives it; `nil` for a root class
    /// and for a superclass the reader cannot name. Read by `index(in:)`.
    public package(set) var superclassName: TypeName?

    /// The protocols the class adopts; read by `index(in:)`.
    public package(set) var protocolNames: [ProtocolName] = []

    /// The members, instance members first, each list in its order; read by
    /// `index(in:)`.
    public package(set) var members: [ObjCImportedMemberDefinition] = []

    /// Whether `index(in:)` has completed a pass over this definition. Safe
    /// to read from any thread.
    public var isIndexed: Bool {
        DefinitionIndexing.isIndexed(self)
    }

    /// The flag behind `isIndexed`; `DefinitionIndexing` alone reads and
    /// writes it, under its lock.
    var hasCompletedIndexing = false

    /// What the image's lists record of the class.
    package let record: ObjCImportedContainerRecord

    package init(record: ObjCImportedContainerRecord, swiftClassDefinition: TypeDefinition?, swiftExtensions: [ExtensionDefinition], in machO: some MachOSwiftSectionRepresentableWithCache) {
        let classNode = ObjCRuntimeNames.classNode(forRuntimeName: record.classRuntimeName, in: machO)
        self.className = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: Node.createTransient(kind: .type, child: classNode), in: machO), kind: .class)
        self.objcRuntimeName = record.classRuntimeName
        self.isSwiftClass = record.isSwiftClass
        self.swiftClassDefinition = swiftClassDefinition
        self.swiftExtensions = swiftExtensions
        self.record = record
    }
}
