import MachOKit
import MachOMacro
import MachOReading
import MachOResolving
import MachOExtensions

public struct Symbol: Resolvable, Hashable {
    public let offset: Int

    public let stringValue: String

    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: offset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from offset: Int, in machO: MachO) throws -> Self? {
        if let symbol = machO.symbols(offset: offset)?.first {
            return symbol
        }
        return nil
    }
}

