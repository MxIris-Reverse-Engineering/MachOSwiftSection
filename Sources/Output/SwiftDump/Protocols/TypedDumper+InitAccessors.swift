import Semantic
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

extension TypedDumper {
    /// The line above `symbol` when it is a SE-0400 init accessor (evolution
    /// proposal `init-accessor-recovery`): the fields the dumped type's
    /// records say it initializes — inferred, since no image records
    /// `@storageRestrictions` — or that the binary does not record them.
    /// Empty for every other symbol.
    @SemanticStringBuilder
    package func initAccessorFieldsComment(for symbol: DemangledSymbol) -> SemanticString {
        if symbol.demangledNode.children.contains(where: { $0.kind == .initAccessor }) {
            configuration.initAccessorFieldsComment(initializedFieldNames: initializedFieldNames(ofInitAccessor: symbol))
        }
    }

    /// What `InitAccessorFieldInference` reads off the dumped type's field
    /// records for the init accessor `symbol` — the same rule, over the
    /// same symbol, the declaration model applies at index time.
    private func initializedFieldNames(ofInitAccessor symbol: DemangledSymbol) -> [String]? {
        guard let records = try? dumped.descriptor.fieldDescriptor(in: machO.context).records(in: machO.context) else { return nil }
        return InitAccessorFieldInference.initializedFieldNames(ofInitAccessorSymbol: symbol.demangledNode) { fieldName in
            guard let record = records.first(where: { (try? $0.fieldName(in: machO.context)) == fieldName }),
                  let mangledTypeName = try? record.mangledTypeName(in: machO.context),
                  let typeNode = try? fieldDemangledTypeNode(for: mangledTypeName)
            else { return nil }
            return InitAccessorFieldInference.StoredField(name: fieldName, typeNode: typeNode)
        }
    }
}
