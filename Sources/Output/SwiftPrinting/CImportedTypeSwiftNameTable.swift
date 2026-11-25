import Demangling
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import BinaryParseSupport

/// The Swift names the image's own C-imported type descriptors give, keyed by
/// the identity a mangling spells for each type (evolution proposals
/// `c-imported-type-name-spelling`, `consistent-c-imported-type-spelling`).
///
/// IRGen writes a C-imported type's descriptor name as the type's Swift name
/// and, when the C declaration is called something else, appends that C name
/// as the import info's ABI name (`TypeImportInfo`). Every mangled reference
/// spells the C name, so this table is what turns `__C.AGWeakAttribute` back
/// into the `AnyWeakAttribute` its declaration prints — without an SDK, for
/// private frameworks too. A descriptor with no ABI name proves the two names
/// are one, so `__C.AGDescriptionOption` prints as `AGDescriptionOption`, the
/// way its declaration does.
///
/// Only names known to be the type's whole Swift name are kept; see
/// ``knownSwiftName(ofDescriptorNamed:importInfo:isDirectlyInImportedModule:)``.
struct CImportedTypeSwiftNameTable: Sendable {
    static let empty = Self(swiftNamesByIdentity: [:])

    /// Keyed by the identity node with any `type` wrapper taken off. `Node`
    /// hashes and compares by structure, so a reference demangled from a
    /// symbol finds the entry built from the descriptor.
    private let swiftNamesByIdentity: [Node: String]

    private init(swiftNamesByIdentity: [Node: String]) {
        self.swiftNamesByIdentity = swiftNamesByIdentity
    }

    /// Reads every C-imported type descriptor of the image. A descriptor that
    /// cannot be read is left out: a missing entry only keeps that type's C
    /// name.
    init(typeContextDescriptors: [TypeContextDescriptorWrapper], in context: some ReadingContext) {
        var swiftNamesByIdentity: [Node: String] = [:]
        for descriptorWrapper in typeContextDescriptors {
            let descriptor = descriptorWrapper.typeContextDescriptor
            guard (try? descriptor.isCImportedContextDescriptor(in: context)) == true,
                  let userFacingName = try? descriptorWrapper.namedContextDescriptor.name(in: context)
            else { continue }
            let importInfo: TypeImportInfo?
            if descriptor.hasImportInfo {
                // An import info that cannot be read is not an absent one: it
                // may carry the C name.
                guard let readImportInfo = try? descriptor.typeImportInfo(in: context) else { continue }
                importInfo = readImportInfo
            } else {
                importInfo = nil
            }
            // What the import info rules out — a related entity, a rename
            // that is not trusted — is ruled out wherever the type sits, so it
            // is settled before the demangle the key needs.
            guard Self.knownSwiftName(ofDescriptorNamed: userFacingName, importInfo: importInfo, isDirectlyInImportedModule: true) != nil,
                  let identity = try? SymbolicDemangler.demangleContext(for: descriptorWrapper.asContextDescriptorWrapper, in: context)
            else { continue }
            let identityKey = Self.key(for: identity)
            let isDirectlyInImportedModule = identityKey.children.first?.kind == .module
            guard let swiftName = Self.knownSwiftName(ofDescriptorNamed: userFacingName, importInfo: importInfo, isDirectlyInImportedModule: isDirectlyInImportedModule) else { continue }
            swiftNamesByIdentity[identityKey] = swiftName
        }
        self.swiftNamesByIdentity = swiftNamesByIdentity
    }

    /// The known Swift name of the C-imported type `identity` names — a
    /// nominal node as a mangling spells it, with or without a `type` wrapper
    /// — or nil.
    func swiftName(forIdentity identity: Node) -> String? {
        guard !swiftNamesByIdentity.isEmpty else { return nil }
        return swiftNamesByIdentity[Self.key(for: identity)]
    }

    var isEmpty: Bool {
        swiftNamesByIdentity.isEmpty
    }

    /// Whether a descriptor's user-facing name is the type's whole Swift name.
    ///
    /// - It has to differ from the ABI name, or there is nothing to rename.
    /// - An importer-synthesized related entity (the error struct of an
    ///   `NS_ERROR_ENUM`) is spelled through its original declaration, not
    ///   renamed.
    /// - A type imported as a member (`NS_SWIFT_NAME(NSAttributedString.Key)`)
    ///   keeps only its leaf in the descriptor (`Key`), and nothing in the
    ///   binary names the type it is a member of. Such a C name ends with the
    ///   leaf (`NSAttributedStringKey`), so a name the ABI name ends with is
    ///   not trusted. A top-level rename shaped the same way (`NSDecimal` to
    ///   `Decimal`) is refused with them and keeps its C name.
    static func trustsUserFacingName(_ userFacingName: String, importInfo: TypeImportInfo) -> Bool {
        guard let abiName = importInfo.abiName, abiName != userFacingName, !importInfo.isRelatedEntity else { return false }
        return !abiName.hasSuffix(userFacingName)
    }

    /// The Swift name a C-imported type's descriptor name is known to be, or
    /// nil.
    ///
    /// - No ABI name (no import info at all, or one carrying only the symbol
    ///   namespace): IRGen writes the ABI name only when the C declaration's
    ///   name differs from the Swift one (`computeIdentity` in
    ///   `lib/IRGen/GenMeta.cpp`), so the descriptor's name is both — for a
    ///   type directly in `__C` / `__C_Synthesized`. A type nested in a C
    ///   type (`__Unnamed_struct__details`) is never looked up by its own
    ///   name: its parent's reference spells it.
    /// - An ABI name: the descriptor's name when it is the type's whole Swift
    ///   name (``trustsUserFacingName(_:importInfo:)``).
    /// - An importer-synthesized related entity: never; it is spelled
    ///   through its original declaration.
    ///
    /// The one shape this gets wrong is a type imported as a member of
    /// another under its own unprefixed C name (`swift_name("Owner.Foo")` on
    /// a C `Foo`): the leaf equals the C name, so no ABI name is written,
    /// yet Swift spells it `Owner.Foo`. No SDK type is named that way.
    static func knownSwiftName(ofDescriptorNamed userFacingName: String, importInfo: TypeImportInfo?, isDirectlyInImportedModule: Bool) -> String? {
        if let importInfo, importInfo.isRelatedEntity {
            return nil
        }
        if let importInfo, let abiName = importInfo.abiName, abiName != userFacingName {
            return trustsUserFacingName(userFacingName, importInfo: importInfo) ? userFacingName : nil
        }
        return isDirectlyInImportedModule ? userFacingName : nil
    }

    private static func key(for identity: Node) -> Node {
        var node = identity
        while node.kind == .type, let wrapped = node.children.first {
            node = wrapped
        }
        return node
    }
}
