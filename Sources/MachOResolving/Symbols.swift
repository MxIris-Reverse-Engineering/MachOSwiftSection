/// Every symbol found at one offset.
///
/// Identical code folding leaves several names at one address, so a
/// symbol lookup answers with a collection rather than a single `Symbol`.
/// The resolution layer only defines the collection; `MachOSymbols`
/// populates it from its per-image index.
public struct Symbols: Sendable {
    public let offset: Int

    private var _storage: [Symbol] = []

    package init(offset: Int, symbols: [Symbol]) {
        self.offset = offset
        self._storage = symbols
    }
}

extension Symbols: RandomAccessCollection {
    public typealias Element = Symbol

    public var startIndex: Int { _storage.startIndex }

    public var endIndex: Int { _storage.endIndex }

    public func index(after i: Int) -> Int {
        _storage.index(after: i)
    }
}

extension Symbols: MutableCollection {
    public subscript(position: Int) -> Symbol {
        get {
            _storage[position]
        }
        set {
            _storage[position] = newValue
        }
    }

    public mutating func append(_ newElement: Symbol) {
        _storage.append(newElement)
    }

    public mutating func remove(at index: Int) {
        _storage.remove(at: index)
    }

    public mutating func removeAll() {
        _storage.removeAll()
    }
}
