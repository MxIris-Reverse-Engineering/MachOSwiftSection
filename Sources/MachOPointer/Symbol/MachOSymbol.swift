import MachOKit
import MachOMacro
import MachOExtensions
import MachOReading

public struct MachOSymbol: Resolvable {
    enum Error: Swift.Error {
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
        guard let symbol = try resolve(from: fileOffset, in: machOFile) else { throw Error.symbolNotFound }
        return symbol
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        if let symbol = machOFile.findSymbol(offset: fileOffset) {
            return symbol
        }
        if let symbol = machOFile.symbol(for: fileOffset) {
            return MachOSymbol(offset: symbol.offset, stringValue: symbol.name)
        }
        return nil
    }
}
