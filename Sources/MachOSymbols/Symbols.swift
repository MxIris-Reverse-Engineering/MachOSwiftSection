import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public struct Symbols: Resolvable {
    private var _storage: [Symbol] = []

    public let offset: Int

    internal init(offset: Int, symbols: [Symbol]) {
        self.offset = offset
        self._storage = symbols
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        try required(resolve(from: fileOffset, in: machOFile))
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        return machOFile.symbols(offset: fileOffset)
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
