import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// An extension the image declares of a class another module declares, in
/// which it adopts Objective-C protocols (evolution proposal
/// `swift-declared-objc-protocols`) — known from the extension's category,
/// since an `@objc` protocol has no witness table and so no conformance
/// record names it. The compiler emits a category only for a class of
/// another module: it folds an extension of the class's own module into the
/// class's data (``TypeDefinition/objcProtocolNames``).
public struct ObjCCategoryConformance: Sendable {
    /// The extended class, `Type > Class`: an Objective-C class in `__C`, or
    /// a Swift class of another module.
    public let extendedTypeName: TypeName

    /// The protocols the extension adopts, in the category's order, without
    /// those a Swift protocol the image conforms the class to inherits.
    public let protocolNames: [ProtocolName]

    package init(extendedTypeName: TypeName, protocolNames: [ProtocolName]) {
        self.extendedTypeName = extendedTypeName
        self.protocolNames = protocolNames
    }

    /// The image's, in category-list order. A category whose every protocol
    /// is implied gives none.
    package static func all(in machO: some MachOSwiftSectionRepresentableWithCache) -> [ObjCCategoryConformance] {
        ObjCProtocolAdoptionIndex.shared.categoryAdoptions(in: machO).compactMap { categoryAdoption in
            let protocolNames = ObjCProtocolNames.protocolNames(categoryAdoption.protocolRuntimeNames, excluding: categoryAdoption.impliedProtocolRuntimeNames, in: machO)
            guard !protocolNames.isEmpty else { return nil }
            let typeNode = Node.createTransient(kind: .type, child: ObjCRuntimeNames.classNode(forRuntimeName: categoryAdoption.classRuntimeName, in: machO))
            let extendedTypeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: .class)
            return ObjCCategoryConformance(extendedTypeName: extendedTypeName, protocolNames: protocolNames)
        }
    }
}
