import Demangling
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import BinaryParseSupport

/// The Swift names the image's own C-imported type descriptors give, keyed by
/// the identity a mangling spells for each type (evolution proposal
/// `c-imported-type-name-spelling`).
///
/// IRGen writes a C-imported type's descriptor name as the type's Swift name
/// and, when the C declaration is called something else, appends that C name
/// as the import info's ABI name (`TypeImportInfo`). Every mangled reference
/// spells the C name, so this table is what turns `__C.AGWeakAttribute` back
/// into the `AnyWeakAttribute` its declaration prints — without an SDK, for
/// private frameworks too.
///
/// Only names that are the type's whole Swift name are kept; see
/// ``trustsUserFacingName(_:importInfo:)``.
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
            guard descriptor.hasImportInfo,
                  (try? descriptor.isCImportedContextDescriptor(in: context)) == true,
                  let importInfo = try? descriptor.typeImportInfo(in: context),
                  let userFacingName = try? descriptorWrapper.namedContextDescriptor.name(in: context),
                  Self.trustsUserFacingName(userFacingName, importInfo: importInfo),
                  let identity = try? SymbolicDemangler.demangleContext(for: descriptorWrapper.asContextDescriptorWrapper, in: context)
            else { continue }
            swiftNamesByIdentity[Self.key(for: identity)] = userFacingName
        }
        self.swiftNamesByIdentity = swiftNamesByIdentity
    }

    /// The trusted Swift name of the C-imported type `identity` names — a
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

    private static func key(for identity: Node) -> Node {
        var node = identity
        while node.kind == .type, let wrapped = node.children.first {
            node = wrapped
        }
        return node
    }
}
