import MachOKit

import MachOReading
import MachOResolving
import MachOExtensions

public struct Symbols: Resolvable {
    private var _storage: [Symbol] = []

    public let offset: Int

    internal init(offset: Int, symbols: [Symbol]) {
        self.offset = offset
        self._storage = symbols
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: offset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        return machO.symbols(offset: offset)
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
