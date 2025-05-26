import Foundation
import MachOKit
import MachOSwiftSectionMacro

enum ResolvableError: Error {
    case symbolNotFound
}

public struct UnsolvedSymbol: Resolvable {
    public let offset: Int

    public let stringValue: String

    public init(offset: Int, stringValue: String) {
        self.offset = offset
        self.stringValue = stringValue
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> UnsolvedSymbol {
        guard let symbol = try resolve(from: fileOffset, in: machOFile) else { throw ResolvableError.symbolNotFound }
        return symbol
    }

    @MachOImageGenerator
    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> UnsolvedSymbol? {
        guard let symbol = machOFile.symbol(for: fileOffset) else { return nil }
        return .init(offset: symbol.offset, stringValue: symbol.name)
    }
}
