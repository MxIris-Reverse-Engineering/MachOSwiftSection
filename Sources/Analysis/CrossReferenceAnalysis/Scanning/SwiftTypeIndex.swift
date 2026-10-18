import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// The Swift types one image defines, by the addresses code reaches them
/// through: every type context descriptor its `__swift5_types` lists, and
/// each descriptor's metadata accessor.
///
/// Built per image on first use. A type's key — its nominal mangling,
/// `7SwiftUI4TextV` — is built only when someone asks for it: it takes
/// demangling the descriptor's context, tens of microseconds a type.
final class SwiftTypeIndex: @unchecked Sendable {
    /// User-space addresses fit in 47 bits; above them are pointer
    /// authentication bits.
    static let addressMask: UInt64 = 0x0000_7FFF_FFFF_FFFF

    private let image: MachOImage
    private let imageIndex: Int
    private let slide: Int
    private let descriptorsByRuntimeAddress: [UInt: TypeContextDescriptorWrapper]
    private let descriptorsByAccessor: [UInt: UInt]
    private let lock = NSLock()
    private var keysByDescriptor: [UInt: String?] = [:]
    private var descriptorSymbolsStorage: [UInt: String]?

    init(image: MachOImage, imageIndex: Int) {
        self.image = image
        self.imageIndex = imageIndex
        self.slide = image.vmaddrSlide ?? 0
        var descriptors: [UInt: TypeContextDescriptorWrapper] = [:]
        var accessors: [UInt: UInt] = [:]
        let base = UInt(bitPattern: image.ptr)
        for wrapper in (try? image.swift.typeContextDescriptors) ?? [] {
            let descriptor = base &+ UInt(bitPattern: wrapper.typeContextDescriptor.offset)
            descriptors[descriptor] = wrapper
            // Every type context descriptor holds its metadata accessor as a
            // relative direct pointer at +12.
            guard let field = UnsafeRawPointer(bitPattern: descriptor &+ 12) else { continue }
            let relative = field.loadUnaligned(as: Int32.self)
            guard relative != 0 else { continue }
            accessors[UInt(bitPattern: Int(bitPattern: descriptor &+ 12) &+ Int(relative))] = descriptor
        }
        self.descriptorsByRuntimeAddress = descriptors
        self.descriptorsByAccessor = accessors
    }

    /// The descriptor of the type whose metadata accessor starts at the
    /// runtime `address`.
    func descriptorLocation(ofAccessorAt address: UInt) -> CodeLocation? {
        descriptorsByAccessor[address].map(location(ofRuntimeAddress:))
    }

    /// Whether a type context descriptor of this image lies at the runtime
    /// `address`.
    func describesType(descriptorAt address: UInt) -> Bool {
        descriptorsByRuntimeAddress[address] != nil
    }

    /// The runtime address of the metadata accessor of the type whose
    /// descriptor lies at the runtime `descriptor`.
    func accessorAddress(ofDescriptorAt descriptor: UInt) -> UInt? {
        guard descriptorsByRuntimeAddress[descriptor] != nil, let field = UnsafeRawPointer(bitPattern: descriptor &+ 12) else { return nil }
        let relative = field.loadUnaligned(as: Int32.self)
        return relative == 0 ? nil : UInt(bitPattern: Int(bitPattern: descriptor &+ 12) &+ Int(relative))
    }

    /// The key of the type whose descriptor lies at the runtime `address`,
    /// `7SwiftUI4TextV`: the type its `…Mn` symbol names, demangled and
    /// mangled again, so that it is spelled as the keys of demangled names
    /// and symbols are. Without a symbol, the descriptor's context is
    /// demangled instead, which spells a type in a constrained extension with
    /// the extension's requirements (`7SwiftUI7ForEachVAASkRzSHR_rlE16PlaceholderViewsV`
    /// for the symbol's `7SwiftUI7ForEachVAAE16PlaceholderViewsV`, 58 of
    /// SwiftUICore's accessor calls) and loses a private type an extension of
    /// another module's type holds — Foundation's
    /// `Mutex<…>.LockResult` comes out as `15Synchronization5MutexV`.
    func key(ofDescriptorAt address: UInt) -> String? {
        guard let wrapper = descriptorsByRuntimeAddress[address] else { return nil }
        lock.lock()
        if let known = keysByDescriptor[address] {
            lock.unlock()
            return known
        }
        lock.unlock()
        var key: String?
        // Demangled for the key alone: the shared `NodeCache` would keep
        // every type's tree for the life of the process.
        if let symbol = descriptorSymbols()[address], let node = try? demangleAsNodeTransient(symbol) {
            key = CrossReferenceAnalyzer.nominalKeys(in: node).first
        }
        if key == nil, let contextNode = try? SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: image.context) {
            key = try? mangleAsString(NodeBuilder(kind: .type, children: [contextNode]).node)
        }
        lock.lock()
        keysByDescriptor[address] = key
        lock.unlock()
        return key
    }

    /// The `$s…Mn` symbol at each descriptor, from the symbol table and the
    /// export trie, without the leading underscore; read on first use.
    private func descriptorSymbols() -> [UInt: String] {
        lock.lock()
        defer { lock.unlock() }
        if let descriptorSymbolsStorage { return descriptorSymbolsStorage }
        var symbols: [UInt: String] = [:]
        func consider(_ name: UnsafePointer<CChar>, at address: UInt) {
            guard symbols[address] == nil, descriptorsByRuntimeAddress[address] != nil, name[0] == 0x5F, name[1] == 0x24 else { return }
            let length = strlen(name)
            guard length > 4, name[length - 2] == 0x4D, name[length - 1] == 0x6E else { return }
            symbols[address] = String(cString: name + 1)
        }
        if let symbolTable = image.symbols64 {
            for symbolIndex in 0 ..< symbolTable.numberOfSymbols {
                let entry = symbolTable.symbols[symbolIndex]
                // Defined in a section, not a debugging entry.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E else { continue }
                consider(symbolTable.stringBase.advanced(by: Int(entry.n_un.n_strx)), at: UInt(bitPattern: Int(bitPattern: UInt(entry.n_value)) &+ slide))
            }
        }
        let base = UInt(bitPattern: image.ptr)
        for exported in image.exportedSymbols {
            guard let offset = exported.offset, exported.name.hasSuffix("Mn") else { continue }
            exported.name.withCString { consider($0, at: base &+ UInt(bitPattern: offset)) }
        }
        descriptorSymbolsStorage = symbols
        return symbols
    }

    /// Where the types whose key is `key` lie. Only the types whose
    /// descriptors give them the name the key ends in — `Text` for
    /// `7SwiftUI4TextV` — have their keys built and compared: building every
    /// type's key, a demangle each, took AppKit's first lookup 0.7 s in a
    /// debug build. A key whose name cannot be read is compared with every
    /// type's.
    func descriptorLocations(withKey key: String) -> [CodeLocation] {
        var candidates = Array(descriptorsByRuntimeAddress.keys)
        if let typeName = Self.typeName(inKey: key) {
            candidates = typeName.withCString { wantedName in
                candidates.filter { Self.descriptor(at: $0, isNamed: wantedName) }
            }
        }
        return candidates.compactMap { address in
            self.key(ofDescriptorAt: address) == key ? location(ofRuntimeAddress: address) : nil
        }
    }

    /// Whether the descriptor at the runtime `address` gives its type the
    /// name `wantedName`: the name it is declared with, or — for a type
    /// imported from C or Objective-C under another Swift name — the name it
    /// has there, which a key spells and the descriptor's import info keeps
    /// after the name: `ResponseDisposition`, then
    /// `NNSURLSessionResponseDisposition`.
    static func descriptor(at address: UInt, isNamed wantedName: UnsafePointer<CChar>) -> Bool {
        guard let name = name(ofDescriptorAt: address) else { return false }
        if strcmp(name, wantedName) == 0 { return true }
        guard hasImportInfo(descriptorAt: address) else { return false }
        // Null-terminated strings, each starting with a tag, until an empty one.
        var component = name + strlen(name) + 1
        while component[0] != 0 {
            if component[0] == 0x4E /* N: the ABI name */, strcmp(component + 1, wantedName) == 0 { return true }
            component += strlen(component) + 1
        }
        return false
    }

    /// `TypeContextDescriptorFlags::HasImportInfo`: the third of the
    /// kind-specific flags, the upper half of the descriptor's first word.
    private static func hasImportInfo(descriptorAt address: UInt) -> Bool {
        guard let descriptor = UnsafeRawPointer(bitPattern: address) else { return false }
        return descriptor.loadUnaligned(as: UInt32.self) & (1 << 18) != 0
    }

    /// The name the key's type is declared with — `Text` for
    /// `7SwiftUI4TextV`, `Storage` for a private or a local `Storage` — which
    /// is the name its descriptor gives it. Demangled for this call alone.
    static func typeName(inKey key: String) -> String? {
        // Global › TypeMetadata › Type › the nominal type: context, name.
        guard let node = try? demangleAsNodeTransient("$s" + key + "N"),
              let nominal = node.children.first?.children.first?.children.first,
              nominal.children.count >= 2
        else { return nil }
        let nameNode = nominal.children[1]
        switch nameNode.kind {
        case .identifier:
            return nameNode.text
        case .privateDeclName, .localDeclName:
            return nameNode.children.last?.text
        default:
            return nil
        }
    }

    /// Reads the descriptors' symbols now, which the first key built would.
    func readDescriptorSymbols() {
        _ = descriptorSymbols()
    }

    /// Where every type's descriptor lies; for tests.
    var descriptorAddresses: [UInt] {
        Array(descriptorsByRuntimeAddress.keys)
    }

    /// Whether the descriptors' symbols have been read, and how many keys
    /// are built; for tests.
    var builtState: (hasReadDescriptorSymbols: Bool, keyCount: Int, typeCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (descriptorSymbolsStorage != nil, keysByDescriptor.count, descriptorsByRuntimeAddress.count)
    }

    /// The memory the index takes, with the symbols read and the keys built;
    /// see `ApproximateSize`.
    var approximateByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        var byteCount = ApproximateSize.of(descriptorsByRuntimeAddress) + ApproximateSize.of(descriptorsByAccessor) + ApproximateSize.of(keysByDescriptor)
        byteCount = keysByDescriptor.values.reduce(byteCount) { $0 + ($1.map(ApproximateSize.of) ?? 0) }
        if let descriptorSymbolsStorage {
            byteCount = descriptorSymbolsStorage.values.reduce(byteCount + ApproximateSize.of(descriptorSymbolsStorage)) { $0 + ApproximateSize.of($1) }
        }
        return byteCount
    }

    /// The name a descriptor gives its type, `Text` — for a type declared in
    /// Swift, the last component of its key — read without demangling.
    static func name(ofDescriptorAt address: UInt) -> UnsafePointer<CChar>? {
        guard let field = UnsafeRawPointer(bitPattern: address &+ 8) else { return nil }
        let relative = field.loadUnaligned(as: Int32.self)
        guard relative != 0 else { return nil }
        return UnsafePointer<CChar>(bitPattern: UInt(bitPattern: Int(bitPattern: address &+ 8) &+ Int(relative)))
    }

    func location(ofRuntimeAddress address: UInt) -> CodeLocation {
        CodeLocation(imageIndex: imageIndex, address: UInt64(bitPattern: Int64(bitPattern: UInt64(address)) &- Int64(slide)))
    }
}
