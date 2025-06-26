import MachOKit
import MachOMacro
import MachOReading
import MachOExtensions

public struct Symbol: Resolvable, Hashable {
    public enum ResolveError: Swift.Error {
        case symbolNotFound
    }

    public let offset: Int

    public let stringValue: String

    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self {
        guard let symbol = try resolve(from: fileOffset, in: machOFile) else { throw ResolveError.symbolNotFound }
        return symbol
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        if let symbol = machOFile.findSymbol(offset: fileOffset) {
            return symbol
        }
        return nil
    }
}
