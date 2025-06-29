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

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        try required(resolve(from: fileOffset, in: machOFile))
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        if let symbol = machOFile.symbols(offset: fileOffset)?.first {
            return symbol
        }
        return nil
    }
}

