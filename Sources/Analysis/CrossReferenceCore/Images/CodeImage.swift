import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import CodeAddressResolution

/// One image an analyzer covers, as the core and the language layers read
/// it.
///
/// Its load commands are read through MachOKit — `reader` is a `MachOImage`
/// for the in-process analyzer and a `MachOFile` for one made from files —
/// and the tables of its `__LINKEDIT` straight from the analyzer's memory
/// (``ImageLinkEdit``), which works the same way for both. What differs
/// between the two kinds of reader is decided once, where the analyzer makes
/// its images: what to add to an unslid address to reach the analyzer's
/// address space, and where an offset the reader's own APIs hand out —
/// MachOSwiftSection's and MachOObjCSection's — lies.
package struct CodeImage: @unchecked Sendable {
    /// The image as MachOKit reads it. Asked what it is only through
    /// `asMachOImage` / `asMachOFile`, by a layer whose library has an API
    /// per kind of reader.
    package let reader: any MachORepresentableWithCache
    /// Where dyld loaded the image — for a shared cache image, its install
    /// name — or the path of the file it was read from.
    package let path: String
    /// The name load commands link the image by, when it is a dylib.
    package let installName: String?
    /// What to add to an unslid address of the image to reach the analyzer's
    /// address space: the image's slide in this process, 0 in a file.
    package let slide: Int
    /// The unslid address of the Mach header — `__TEXT`'s vmaddr.
    package let headerAddress: UInt64
    /// Whether the image is part of a dyld shared cache.
    package let isInSharedCache: Bool
    private let unslidAddressOfReaderOffset: @Sendable (Int) -> UInt64?
    private let readerOffsetOfUnslidAddress: @Sendable (UInt64) -> Int?

    /// An image mapped into this process. `path` is where dyld loaded it.
    package init(image: MachOImage, path: String) {
        let headerAddress = Self.textAddress(of: image)
        self.reader = image
        self.path = path
        self.installName = image.path
        self.slide = image.vmaddrSlide ?? 0
        self.headerAddress = headerAddress
        self.isInSharedCache = image.header.isInDyldCache
        // A `MachOImage`'s offsets count from its Mach header.
        self.unslidAddressOfReaderOffset = { offset in UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset)) }
        self.readerOffsetOfUnslidAddress = { address in Int(truncatingIfNeeded: Int64(bitPattern: address &- headerAddress)) }
    }

    /// An image read from a file: one of a dyld shared cache's, at its own
    /// addresses, or a standalone Mach-O, at `slide` from them — what keeps
    /// the address ranges of several files apart.
    package init(file: MachOFile, slide: Int = 0) {
        // A cache image's offsets are its addresses less the shared region's
        // start, a standalone file's are file offsets: `ImageAddressSpace`
        // knows both.
        let addressSpace = ImageAddressSpace(of: file)
        self.reader = file
        var installName: String?
        for case .idDylib(let command) in file.loadCommands {
            installName = command.dylib(in: file).name
        }
        // A cache image goes by its install name; a standalone file by its
        // path, since a framework's install name (`@rpath/…`) names no file.
        self.path = file.isLoadedFromDyldCache ? file.imagePath : file.url.path
        self.installName = installName
        self.slide = slide
        self.headerAddress = Self.textAddress(of: file)
        self.isInSharedCache = file.isLoadedFromDyldCache
        self.unslidAddressOfReaderOffset = { offset in addressSpace.address(forOffset: offset) }
        self.readerOffsetOfUnslidAddress = { address in addressSpace.offset(forAddress: address) }
    }

    private static func textAddress(of reader: some MachORepresentable) -> UInt64 {
        reader.segments64.first { $0.segmentName == "__TEXT" }.map { UInt64($0.layout.vmaddr) } ?? 0
    }

    /// The unslid address of an offset the reader's own APIs hand out.
    package func unslidAddress(ofReaderOffset offset: Int) -> UInt64? {
        unslidAddressOfReaderOffset(offset)
    }

    /// The offset the reader's own APIs take for the unslid `address`.
    package func readerOffset(ofUnslidAddress address: UInt64) -> Int? {
        readerOffsetOfUnslidAddress(address)
    }

    /// Where the unslid `address` lies in the analyzer's address space.
    package func runtimeAddress(ofUnslid address: UInt64) -> UInt {
        UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
    }

    /// The unslid address of the runtime `address`.
    package func unslidAddress(ofRuntime address: UInt) -> UInt64 {
        UInt64(bitPattern: Int64(Int(bitPattern: address) &- slide))
    }

    /// The unslid address `offset` bytes from the Mach header — an export
    /// trie's offsets count from there. Offsets may be negative: in a shared
    /// cache, an export can lie below the image's own header.
    package func unslidAddress(atHeaderOffset offset: Int) -> UInt64 {
        UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset))
    }
}

/// The tables of an image's `__LINKEDIT` the analysis reads, where they lie
/// in the analyzer's memory.
///
/// A table lies at `__LINKEDIT`'s address plus its offset, less the
/// segment's own file offset: the address MachOKit's `MachOImage` reads it
/// at, and one a file's mapping answers as well — for a shared cache image,
/// the offsets in its load commands count in the cache file that holds the
/// shared `__LINKEDIT`, as the segment's does. So the core reads every image
/// the same way, whatever its reader.
package struct ImageLinkEdit: @unchecked Sendable {
    /// `LC_SYMTAB`'s symbols, and the strings their names index.
    package let symbols: UnsafeBufferPointer<nlist_64>
    private let strings: UnsafePointer<CChar>?
    /// `LC_DYSYMTAB`'s indirect symbol table: for each stub and lazy or
    /// non-lazy pointer, the index of the symbol it stands for.
    package let indirectSymbols: UnsafeBufferPointer<UInt32>
    /// `LC_DYSYMTAB`'s undefined symbols, by index into ``symbols``.
    package let undefinedSymbolRange: Range<Int>?
    /// `LC_FUNCTION_STARTS`, ULEB128-encoded deltas.
    package let functionStarts: UnsafeRawBufferPointer?
    /// `LC_DATA_IN_CODE`.
    package let dataInCode: UnsafeBufferPointer<data_in_code_entry>
    /// `LC_DYLD_EXPORTS_TRIE`, or `LC_DYLD_INFO`'s export trie.
    package let exportTrie: UnsafeRawBufferPointer?

    /// `INDIRECT_SYMBOL_LOCAL` and `INDIRECT_SYMBOL_ABS`: an indirect entry
    /// that names no symbol.
    package static let indirectSymbolLocal: UInt32 = 0x8000_0000
    package static let indirectSymbolAbsolute: UInt32 = 0x4000_0000

    package init(image: CodeImage, memory: any CrossReferenceMemory) {
        let loadCommands = Array(image.reader.loadCommands)
        var linkEditBase: UInt64?
        var symbolTable: symtab_command?
        var dynamicSymbolTable: dysymtab_command?
        var functionStartsCommand: linkedit_data_command?
        var dataInCodeCommand: linkedit_data_command?
        var exportTrieRange: (offset: UInt32, size: UInt32)?
        for command in loadCommands {
            switch command {
            case .segment64(let segment) where segment.segmentName == "__LINKEDIT":
                linkEditBase = UInt64(segment.layout.vmaddr) &- UInt64(segment.layout.fileoff)
            case .symtab(let command):
                symbolTable = command.layout
            case .dysymtab(let command):
                dynamicSymbolTable = command.layout
            case .functionStarts(let command):
                functionStartsCommand = command.layout
            case .dataInCode(let command):
                dataInCodeCommand = command.layout
            case .dyldExportsTrie(let command):
                exportTrieRange = (command.layout.dataoff, command.layout.datasize)
            case .dyldInfo(let command), .dyldInfoOnly(let command):
                if exportTrieRange == nil, command.layout.export_size > 0 {
                    exportTrieRange = (command.layout.export_off, command.layout.export_size)
                }
            default:
                break
            }
        }

        func bytes(atOffset offset: UInt32, size: Int) -> UnsafeRawBufferPointer? {
            guard let linkEditBase, size > 0 else { return nil }
            return memory.bytes(at: image.runtimeAddress(ofUnslid: linkEditBase &+ UInt64(offset)), length: size)
        }
        func table<Element>(of type: Element.Type, atOffset offset: UInt32, count: Int) -> UnsafeBufferPointer<Element> {
            guard count > 0, let buffer = bytes(atOffset: offset, size: count * MemoryLayout<Element>.stride),
                  let start = buffer.baseAddress
            else { return UnsafeBufferPointer(start: nil, count: 0) }
            return UnsafeBufferPointer(start: start.assumingMemoryBound(to: Element.self), count: count)
        }

        if let symbolTable {
            symbols = table(of: nlist_64.self, atOffset: symbolTable.symoff, count: Int(symbolTable.nsyms))
            strings = bytes(atOffset: symbolTable.stroff, size: Int(symbolTable.strsize))?.baseAddress?.assumingMemoryBound(to: CChar.self)
        } else {
            symbols = UnsafeBufferPointer(start: nil, count: 0)
            strings = nil
        }
        if let dynamicSymbolTable {
            indirectSymbols = table(of: UInt32.self, atOffset: dynamicSymbolTable.indirectsymoff, count: Int(dynamicSymbolTable.nindirectsyms))
            let first = Int(dynamicSymbolTable.iundefsym)
            let count = Int(dynamicSymbolTable.nundefsym)
            undefinedSymbolRange = first + count <= symbols.count ? first ..< first + count : nil
        } else {
            indirectSymbols = UnsafeBufferPointer(start: nil, count: 0)
            undefinedSymbolRange = nil
        }
        functionStarts = functionStartsCommand.flatMap { bytes(atOffset: $0.dataoff, size: Int($0.datasize)) }
        if let dataInCodeCommand {
            dataInCode = table(of: data_in_code_entry.self, atOffset: dataInCodeCommand.dataoff, count: Int(dataInCodeCommand.datasize) / MemoryLayout<data_in_code_entry>.stride)
        } else {
            dataInCode = UnsafeBufferPointer(start: nil, count: 0)
        }
        exportTrie = exportTrieRange.flatMap { bytes(atOffset: $0.offset, size: Int($0.size)) }
    }

    /// The export trie's entry for `name`, spelled as the trie spells it
    /// (`_$s…`, `_CFRelease`): looked up in the trie, not read whole.
    package func exportedSymbol(named name: String) -> ExportedSymbol? {
        guard let exportTrie, let base = exportTrie.baseAddress, !exportTrie.isEmpty else { return nil }
        return MemoryTrieTree<ExportTrieNodeContent>(basePointer: base, size: exportTrie.count).search(by: name)
    }

    /// The name of the symbol at `index` in ``symbols``; `nil` when the image
    /// has no string table.
    package func name(ofSymbolAt index: Int) -> UnsafePointer<CChar>? {
        strings.map { $0.advanced(by: Int(symbols[index].n_un.n_strx)) }
    }

    /// Whether the symbol is defined in a section and is no debugging entry.
    package static func isDefinedInSection(_ entry: nlist_64) -> Bool {
        entry.n_type & 0xE0 == 0 && entry.n_type & 0x0E == 0x0E
    }

    /// The function starts `LC_FUNCTION_STARTS` lists, unslid: ULEB128 deltas
    /// from `__TEXT`'s address, the first from the address itself, ended by a
    /// zero delta.
    package func functionStartAddresses(textAddress: UInt64) -> [UInt64] {
        guard let functionStarts, let base = functionStarts.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return [] }
        var addresses: [UInt64] = []
        var address = textAddress
        var position = 0
        let end = functionStarts.count
        while position < end {
            var delta: UInt64 = 0
            var shift: UInt64 = 0
            var byte: UInt8 = 0
            repeat {
                guard position < end else { return addresses }
                byte = base[position]
                position += 1
                if shift < 64 { delta |= UInt64(byte & 0x7F) << shift }
                shift += 7
            } while byte & 0x80 != 0
            if delta == 0 { break }
            address &+= delta
            addresses.append(address)
        }
        return addresses
    }
}
