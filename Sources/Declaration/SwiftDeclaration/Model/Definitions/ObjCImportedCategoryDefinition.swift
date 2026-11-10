import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

/// An Objective-C category of the image as Swift imports it (evolution
/// proposal `objc-imported-declarations`): `extension Class: Protocol… { … }`
/// — Swift has no name for a category — its members built from the
/// category's method and property lists by the importer's rules.
///
/// A category Swift wrote — an `@objc @implementation` of a category a header
/// declares, or `extension NSView { @objc func … }` — takes each member from
/// the image's Swift extension of the class implementing it
/// (``swiftExtensions``), paired by selector as for
/// ``ObjCImportedClassDefinition``.
///
/// `@unchecked Sendable` for the reason `TypeDefinition` gives.
public final class ObjCImportedCategoryDefinition: @unchecked Sendable {
    /// The class the category extends, `Type > Class`.
    public let extendedClassName: TypeName

    /// The category's own name: `NSTouchBar` of `NSView(NSTouchBar)`.
    public let categoryName: String

    /// The name the category is listed under, `NSView(NSTouchBar)`.
    public let uniqueName: String

    /// The image's Swift extensions of the class, which implement a category
    /// Swift wrote.
    public let swiftExtensions: [ExtensionDefinition]

    /// The protocols the category adopts; read by `index(in:)`.
    public package(set) var protocolNames: [ProtocolName] = []

    /// The members, instance members first; read by `index(in:)`.
    public package(set) var members: [ObjCImportedMemberDefinition] = []

    /// Whether `index(in:)` has completed a pass over this definition.
    public var isIndexed: Bool {
        DefinitionIndexing.isIndexed(self)
    }

    var hasCompletedIndexing = false

    package let record: ObjCImportedContainerRecord

    package init(record: ObjCImportedContainerRecord, categoryName: String, swiftExtensions: [ExtensionDefinition], in machO: some MachOSwiftSectionRepresentableWithCache) {
        let classNode = ObjCRuntimeNames.classNode(forRuntimeName: record.classRuntimeName, in: machO)
        self.extendedClassName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: Node.createTransient(kind: .type, child: classNode), in: machO), kind: .class)
        self.categoryName = categoryName
        self.uniqueName = record.uniqueName
        self.swiftExtensions = swiftExtensions
        self.record = record
    }
}
