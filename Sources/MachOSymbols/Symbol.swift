import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public struct Symbol: Resolvable, Hashable {
    public let offset: Int

    public let stringValue: String

    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machO: MachO) throws -> Self {
        try required(resolve(from: fileOffset, in: machO))
    }

    public static func resolve<MachO: MachORepresentableWithCache & MachOReadable>(from fileOffset: Int, in machO: MachO) throws -> Self? {
        if let symbol = machO.symbols(offset: fileOffset)?.first {
            return symbol
        }
        return nil
    }
}

