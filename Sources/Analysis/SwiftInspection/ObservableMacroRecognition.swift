@_spi(Internals) import Demangling
import MachOSwiftSection

/// Recognizes a class the Observation module's `@Observable` macro expanded,
/// from what the expansion left in the binary (evolution proposal
/// `observable-macro-folding`).
///
/// The compiler keeps no record of an attached macro, only of what the macro
/// generated. Every class `@Observable` expands stores an
/// `Observation.ObservationRegistrar` in a property named
/// `_$observationRegistrar`, and that property's field record survives a
/// stripped symbol table, so the class is recognized from its field records
/// alone — in an OS framework or a shipped app as much as in a debug build.
///
/// Two look-alikes are told apart:
/// - SwiftData's `@Model` generates a registrar of the same name and type
///   beside its `_$backingData` storage. A class with that field is a
///   persistent model, not an `@Observable` class.
/// - A class that conforms to `Observable` by hand has no registrar field.
///
/// No conformance record is required: an `@Observable` class deriving from
/// another inherits the conformance, and the macro generates none again.
package enum ObservableMacroRecognition {
    /// The stored property the macro adds to every class it expands.
    package static let registrarFieldName = "_$observationRegistrar"

    /// The stored property SwiftData's `@Model` adds beside a registrar of
    /// the same name and type.
    package static let persistentModelBackingDataFieldName = "_$backingData"

    /// The module that declares the macro, its registrar type and its
    /// protocol.
    package static let observationModuleName = "Observation"

    /// The macro's name, which is also the name of the protocol its
    /// generated extension conforms the class to.
    package static let observableName = "Observable"

    /// The macro a stored property the macro leaves alone is declared with.
    package static let observationIgnoredName = "ObservationIgnored"

    /// The type of `registrarFieldName`.
    package static let registrarTypeName = "ObservationRegistrar"

    /// Whether the type `descriptor` describes is a class `@Observable`
    /// expanded. Reads the field records' names, and the type of the one
    /// named `_$observationRegistrar` only when there is one.
    ///
    /// A field descriptor that cannot be read answers `false`: the
    /// definition's own indexing reads the same records and reports the
    /// failure, so this does not report it a second time.
    package static func isObservableClass(_ descriptor: TypeContextDescriptorWrapper, in context: some ReadingContext) -> Bool {
        guard case .class = descriptor,
              let records = try? descriptor.typeContextDescriptor.fieldDescriptor(in: context).records(in: context)
        else { return false }
        var registrarRecord: FieldRecord?
        for record in records {
            guard let fieldName = try? record.fieldName(in: context) else { continue }
            if fieldName == persistentModelBackingDataFieldName {
                return false
            }
            if fieldName == registrarFieldName {
                registrarRecord = record
            }
        }
        guard let registrarRecord,
              let mangledTypeName = try? registrarRecord.mangledTypeName(in: context),
              let registrarTypeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: context)
        else { return false }
        return isObservationRegistrarType(registrarTypeNode)
    }

    /// Whether `typeNode` names `Observation.ObservationRegistrar`, with or
    /// without the `type` node around it.
    package static func isObservationRegistrarType(_ typeNode: Node) -> Bool {
        isNominal(typeNode, kind: .structure, moduleName: observationModuleName, name: registrarTypeName)
    }

    /// Whether `protocolNode` names `Observation.Observable`, the protocol
    /// the macro's generated extension conforms the class to.
    package static func isObservableProtocol(_ protocolNode: Node) -> Bool {
        isNominal(protocolNode, kind: .protocol, moduleName: observationModuleName, name: observableName)
    }

    /// `Observation.Observable` as a name node: the protocol the macro's
    /// generated extension conforms to, whose name the macro shares — what the
    /// interface and the dump print the macro's attribute from, so module
    /// selectors reach it and the attribute links where the protocol does.
    /// Static, so it outlives every print: the interface printer memoizes
    /// fragments by node identity, and a node freed mid-print could hand its
    /// address to another.
    package static let observableAttributeNameNode = nominalTypeNode(.protocol, moduleName: observationModuleName, name: observableName)

    /// `Observation.ObservationIgnored` as a name node, for the attribute of a
    /// stored property the macro left alone. A macro no type shares a name
    /// with; static for the same reason.
    package static let observationIgnoredAttributeNameNode = nominalTypeNode(.structure, moduleName: observationModuleName, name: observationIgnoredName)

    private static func nominalTypeNode(_ kind: Node.Kind, moduleName: String, name: String) -> Node {
        Node.createTransient(kind: .type, child: Node.createTransient(kind: kind, children: [
            Node.createTransient(kind: .module, text: moduleName),
            Node.createTransient(kind: .identifier, text: name),
        ]))
    }

    private static func isNominal(_ node: Node, kind: Node.Kind, moduleName: String, name: String) -> Bool {
        let nominalNode = node.kind == .type ? node.firstChild : node
        guard let nominalNode, nominalNode.kind == kind, nominalNode.children.count == 2,
              let moduleNode = nominalNode.children.first, moduleNode.kind == .module, moduleNode.text == moduleName,
              let identifierNode = nominalNode.children.last, identifierNode.kind == .identifier, identifierNode.text == name
        else { return false }
        return true
    }
}
