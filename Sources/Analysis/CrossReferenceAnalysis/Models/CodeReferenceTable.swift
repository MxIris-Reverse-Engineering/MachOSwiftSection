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
        /// Every reference to the Swift type whose context descriptor lies
        /// there. Names a mangled name holds are not filed: telling them takes
        /// demangling (`CrossReferenceAnalyzer.references(toSwiftType:inImageAt:)`).
        case swiftTypeDescriptor(CodeLocation)
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

    /// Every key some reference in the table has, in no particular order.
    public var keys: some Collection<Key> {
        referenceIndicesByKey.keys
    }

    /// A rough measure of the memory the table holds: the references, their
    /// keys and the index — not the heap storage of the strings they carry.
    /// A selector, class or imported name longer than 15 bytes holds a
    /// buffer of its own, which every reference to that name from one scan
    /// shares.
    public var approximateByteCount: Int {
        references.count * MemoryLayout<CodeReference>.stride
            + referenceIndicesByKey.count * (MemoryLayout<Key>.stride + 48)
            + references.count * MemoryLayout<Int32>.stride
    }
}

extension CodeReferenceTarget {
    /// The key a ``CodeReferenceTable`` files this target under; `nil` for an
    /// indirect call, an unrecognized target or a Swift type name.
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
        case .swiftType(let descriptor):
            return .swiftTypeDescriptor(descriptor)
        case .swiftTypeName, .indirect, .unrecognized:
            return nil
        }
    }
}
