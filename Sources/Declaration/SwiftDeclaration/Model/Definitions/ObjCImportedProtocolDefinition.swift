import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

/// An Objective-C protocol as Swift imports it (evolution proposal
/// `objc-imported-declarations`): `protocol Name: Inherited… { … }`, its
/// requirements built from the image's record of it by the importer's
/// rules, optional ones marked `@objc optional`. An image holds a record of
/// every protocol it adopts or names, not only of the ones it defines.
///
/// An `@objc` protocol declared in Swift has an ``ObjCProtocolDefinition``
/// too, which the image's Swift side lists; this one reads the record the
/// way the importer reads a header, for a protocol of any origin.
///
/// `@unchecked Sendable` for the reason `TypeDefinition` gives.
public final class ObjCImportedProtocolDefinition: @unchecked Sendable {
    /// `Type > Protocol`.
    public let protocolName: ProtocolName

    /// The name the Objective-C runtime registers the protocol under.
    public let objcRuntimeName: String

    /// The protocols it inherits; read by `index(in:)`.
    public package(set) var inheritedProtocolNames: [ProtocolName] = []

    /// The requirements, in the record's order; read by `index(in:)`.
    public package(set) var requirements: [ObjCProtocolRequirementDefinition] = []

    /// Whether `index(in:)` has completed a pass over this definition.
    public var isIndexed: Bool {
        DefinitionIndexing.isIndexed(self)
    }

    var hasCompletedIndexing = false

    package let record: ObjCProtocolRecord

    package init(record: ObjCProtocolRecord, in machO: some MachOSwiftSectionRepresentableWithCache) {
        let protocolNode = ObjCRuntimeNames.protocolNode(forRuntimeName: record.runtimeName, in: machO)
        self.protocolName = ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: Node.createTransient(kind: .type, child: protocolNode), in: machO))
        self.objcRuntimeName = record.runtimeName
        self.record = record
    }
}
