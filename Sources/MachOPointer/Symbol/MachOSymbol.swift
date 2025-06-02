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

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> Self? {
        guard let symbol = machOFile.findSymbol(offset: fileOffset) else { return nil }
        return symbol
    }

    public static func resolve(from imageOffset: Int, in machOImage: MachOImage) throws -> Self? {
        guard let symbol = machOImage.symbol(for: imageOffset) else { return nil }
        return .init(offset: symbol.offset, stringValue: symbol.name)
    }
}
