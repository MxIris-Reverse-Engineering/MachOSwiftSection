/// Every reference the functions of one image make, grouped by what they
/// reference.
///
/// A table is a plain value: the analyzer does not keep it, so a host holds
/// it for as long as it is useful — ``approximateByteCount`` is what to
/// budget it by.
public struct CodeReferenceTable: Sendable {
    /// What references are grouped by.
    public enum Key: Hashable, Sendable {
        case function(CodeLocation)
        /// Every send of the selector, `super` sends included.
        case selector(String)
        case importedSymbol(String)
        /// Every reference to the class, by its runtime name.
        case objectiveCClass(String)
    }

    public let imageIndex: Int
    /// In instruction order within each function, functions in address order.
    public let references: [CodeReference]
    private let referenceIndicesByKey: [Key: [Int32]]

    init(imageIndex: Int, references: [CodeReference]) {
        self.imageIndex = imageIndex
        self.references = references
        var referenceIndicesByKey: [Key: [Int32]] = [:]
        for (index, reference) in references.enumerated() {
            guard let key = reference.target.tableKey else { continue }
            referenceIndicesByKey[key, default: []].append(Int32(index))
        }
        self.referenceIndicesByKey = referenceIndicesByKey
    }

    /// The references to `key`, in table order.
    public func references(to key: Key) -> [CodeReference] {
        referenceIndicesByKey[key]?.map { references[Int($0)] } ?? []
    }

    /// Every key some reference in the table has.
    public var keys: Dictionary<Key, [Int32]>.Keys {
        referenceIndicesByKey.keys
    }

    /// A rough measure of the memory the table holds.
    public var approximateByteCount: Int {
        references.count * MemoryLayout<CodeReference>.stride
            + referenceIndicesByKey.count * (MemoryLayout<Key>.stride + 48)
            + references.count * MemoryLayout<Int32>.stride
    }
}

extension CodeReferenceTarget {
    /// The key a ``CodeReferenceTable`` files this target under; `nil` for an
    /// indirect call or an unrecognized target.
    public var tableKey: CodeReferenceTable.Key? {
        switch self {
        case .function(let location):
            return .function(location)
        case .messageSend(let selector, _), .superMessageSend(let selector, _):
            return .selector(selector)
        case .importedSymbol(let name):
            return .importedSymbol(name)
        case .objectiveCClass(let name, _):
            return .objectiveCClass(name)
        case .typeMetadataAccessor, .mangledTypeName, .indirect, .unrecognized:
            return nil
        }
    }
}
