import Foundation
import MachOKit

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

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> UnsolvedSymbol {
        guard let symbol = try resolve(from: fileOffset, in: machOFile) else { throw ResolvableError.symbolNotFound }
        return symbol
    }

    public static func resolve(from fileOffset: Int, in machOFile: MachOFile) throws -> UnsolvedSymbol? {
        guard let symbol = machOFile.findSymbol(offset: fileOffset) else { return nil }
        return symbol
    }
}
