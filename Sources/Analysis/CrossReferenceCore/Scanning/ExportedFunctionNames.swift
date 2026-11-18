import Foundation
import MachOKit

/// What an image's export trie names, by unslid address: functions in
/// `__text`, and whatever else it exports — the descriptors in
/// `__TEXT,__const` whose symbols name Swift functions among them.
///
/// The first of the names a function the symbol table leaves unnamed is
/// given. A shared cache image's symbol table may hold its local symbols
/// alone (SiriAppIntents' holds two entries; its export trie names 76,318
/// functions), and an iOS device's cache redacts the local ones while the
/// export trie survives. Read when a function is named, never during a scan.
package final class ExportedFunctionNames: ImageFunctionTableAttachment, @unchecked Sendable {
    package let namesByAddress: [UInt64: [String]]
    package let approximateByteCount: Int

    /// The image's names, read on first use and kept with its table.
    package static func of(_ table: ImageFunctionTable) -> ExportedFunctionNames {
        table.attachment(ExportedFunctionNames.self) { ExportedFunctionNames(table: table) }
    }

    private init(table: ImageFunctionTable) {
        var names: [UInt64: [String]] = [:]
        var byteCount = 0
        for symbol in table.image.exportedSymbols {
            guard let offset = symbol.offset else { continue }
            names[table.address(atHeaderOffset: offset), default: []].append(symbol.name)
            byteCount += ApproximateSize.of(symbol.name)
        }
        self.namesByAddress = names
        self.approximateByteCount = names.values.reduce(byteCount + ApproximateSize.of(names)) { $0 + ApproximateSize.of($1) }
    }
}

extension ImageFunctionTable {
    /// The unslid address `offset` bytes from the Mach header. Offsets may be
    /// negative: in a shared cache, an export or an implementation can lie
    /// below the image's own header.
    package func address(atHeaderOffset offset: Int) -> UInt64 {
        UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset))
    }
}
