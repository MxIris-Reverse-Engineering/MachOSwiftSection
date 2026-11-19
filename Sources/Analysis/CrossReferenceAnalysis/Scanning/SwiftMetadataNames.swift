import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences
@_spi(Internals) import SwiftInspection
import Demangling

/// Swift mangled names for the functions an image's symbol table and export
/// trie leave unnamed, rebuilt from the metadata that points at them: every
/// type's metadata accessor (`…Ma`) and singleton completion function
/// (`…Mr`), and every vtable implementation, whose method descriptor's
/// `…Tq` symbol spells it.
///
/// Kept on the image's function table, read when a function is named, never
/// during a scan: reading an image's metadata costs about as much as
/// scanning it. Evolution proposal `cross-reference-analysis`, batch two.
final class SwiftMetadataNames: ImageFunctionTableAttachment, @unchecked Sendable {
    /// Where a Swift function's name comes from.
    private enum Source {
        /// A type's metadata accessor (`Ma`) or singleton completion function
        /// (`Mr`): the type's descriptor, and the suffix the name ends in.
        case typeFunction(descriptor: TypeContextDescriptorWrapper, descriptorAddress: UInt64, suffix: String)
        /// A method whose descriptor's `…Tq` symbol spells its name.
        case method(descriptorAddress: UInt64)
    }

    private let table: ImageFunctionTable
    private let lock = NSLock()
    private var sourcesStorage: [UInt64: Source]?
    /// The `Mn` / `Tq` symbol at each descriptor the sources name.
    private var descriptorSymbolsStorage: [UInt64: String]?
    private var names: [UInt64: String?] = [:]
    /// What the sources read so far take, counted as each is read.
    private var sourceByteCount = 0

    static func of(_ table: ImageFunctionTable) -> SwiftMetadataNames {
        table.attachment(SwiftMetadataNames.self) { SwiftMetadataNames(table: table) }
    }

    static func existing(in table: ImageFunctionTable) -> SwiftMetadataNames? {
        table.existingAttachment(SwiftMetadataNames.self)
    }

    private init(table: ImageFunctionTable) {
        self.table = table
    }

    /// Reads every source now — the metadata and the descriptors' symbols —
    /// for a host that will name functions of the image and wants none of
    /// it read while it waits. Each function's name is still rebuilt the
    /// first time it is asked for.
    func readEverySource() {
        _ = descriptorSymbols()
    }

    /// Whether every source has been read; for tests.
    var hasReadEverySource: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sourcesStorage != nil && descriptorSymbolsStorage != nil
    }

    /// The memory the sources read so far and the names rebuilt take; see
    /// `ApproximateSize`.
    var approximateByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return names.values.reduce(sourceByteCount + ApproximateSize.of(names)) { $0 + ($1.map(ApproximateSize.of) ?? 0) }
    }

    /// The Swift name of the function at `address`, rebuilt from the
    /// metadata that points at it — remembered, since rebuilding a type's
    /// name without its `Mn` symbol takes a demangle and a remangle.
    func name(at address: UInt64) -> String? {
        guard let source = sources()[address] else { return nil }
        lock.lock()
        if let known = names[address] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let name = buildName(from: source)
        lock.lock()
        defer { lock.unlock() }
        names[address] = name
        return name
    }

    private func buildName(from source: Source) -> String? {
        let descriptorSymbols = self.descriptorSymbols()
        switch source {
        case .typeFunction(let descriptor, let descriptorAddress, let suffix):
            if let symbol = descriptorSymbols[descriptorAddress], let typeMangling = Self.mangling(ofSymbol: symbol, suffix: "Mn") {
                return "$s" + typeMangling + suffix
            }
            guard let typeMangling = typeMangling(of: descriptor) else { return nil }
            return "$s" + typeMangling + suffix
        case .method(let descriptorAddress):
            guard let symbol = descriptorSymbols[descriptorAddress], let methodMangling = Self.mangling(ofSymbol: symbol, suffix: "Tq") else { return nil }
            return "$s" + methodMangling
        }
    }

    /// `_$s7SwiftUI4TextVMn` with suffix `Mn` → `7SwiftUI4TextV`.
    private static func mangling(ofSymbol symbol: String, suffix: String) -> String? {
        var mangling = Substring(symbol)
        if mangling.hasPrefix("_") { mangling = mangling.dropFirst() }
        guard mangling.hasPrefix("$s"), mangling.hasSuffix(suffix) else { return nil }
        mangling = mangling.dropFirst(2).dropLast(suffix.count)
        return mangling.isEmpty ? nil : String(mangling)
    }

    /// A type's mangling built from its descriptor, for a type no `Mn`
    /// symbol spells.
    private func typeMangling(of descriptor: TypeContextDescriptorWrapper) -> String? {
        guard let reader = table.image.swiftSectionReader else { return nil }
        return Self.typeMangling(of: descriptor, in: reader)
    }

    private static func typeMangling(of descriptor: TypeContextDescriptorWrapper, in reader: some MachOSwiftSectionRepresentableWithCache) -> String? {
        guard let contextNode = try? SymbolicDemangler.demangleContext(for: descriptor.asContextDescriptorWrapper, in: reader.context) else { return nil }
        return try? mangleAsString(NodeBuilder(kind: .type, children: [contextNode]).node)
    }

    /// The unslid address of an offset MachOSwiftSection hands out.
    private func address(ofReaderOffset offset: Int) -> UInt64? {
        table.image.unslidAddress(ofReaderOffset: offset)
    }

    /// Which functions the metadata names, by address.
    private func sources() -> [UInt64: Source] {
        lock.lock()
        defer { lock.unlock() }
        if let sourcesStorage { return sourcesStorage }
        var sources: [UInt64: Source] = [:]
        if let reader = table.image.swiftSectionReader {
            collectSources(in: reader, into: &sources)
        }
        sourcesStorage = sources
        sourceByteCount += ApproximateSize.of(sources)
        return sources
    }

    private func collectSources(in reader: some MachOSwiftSectionRepresentableWithCache, into sources: inout [UInt64: Source]) {
        let context = reader.context
        let textRange = table.textStart ..< table.textEnd
        for wrapper in (try? reader.swift.typeContextDescriptors) ?? [] {
            guard let descriptorAddress = address(ofReaderOffset: wrapper.typeContextDescriptor.offset) else { continue }
            // Every type context descriptor holds its metadata accessor as a
            // relative direct pointer at +12.
            let accessorField = descriptorAddress &+ 12
            if let accessor = relativeTarget(ofFieldAt: accessorField), textRange.contains(accessor) {
                sources[accessor] = .typeFunction(descriptor: wrapper, descriptorAddress: descriptorAddress, suffix: "Ma")
            }
            guard let typeWrapper = try? TypeContextWrapper.forTypeContextDescriptorWrapper(wrapper, in: context) else { continue }
            var completionOffset: Int?
            switch typeWrapper {
            case .class(let classType):
                completionOffset = classType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
                for method in classType.methodDescriptors {
                    guard let implementationOffset = method.implementationOffset,
                          let implementation = codeAddress(ofImplementationAtOffset: implementationOffset),
                          sources[implementation] == nil,
                          let methodDescriptorAddress = address(ofReaderOffset: method.offset)
                    else { continue }
                    sources[implementation] = .method(descriptorAddress: methodDescriptorAddress)
                }
            case .struct(let structType):
                completionOffset = structType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
            case .enum(let enumType):
                completionOffset = enumType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
            }
            if let completionOffset, let completion = address(ofReaderOffset: completionOffset), textRange.contains(completion) {
                sources[completion] = .typeFunction(descriptor: wrapper, descriptorAddress: descriptorAddress, suffix: "Mr")
            }
        }
    }

    /// An implementation's code: the offset itself when it lies in `__text`,
    /// or — for an async function — the function an async function pointer
    /// record (`{ rel32 function, u32 context size }`) leads to.
    private func codeAddress(ofImplementationAtOffset offset: Int) -> UInt64? {
        let textRange = table.textStart ..< table.textEnd
        guard let implementation = address(ofReaderOffset: offset) else { return nil }
        if textRange.contains(implementation) { return implementation }
        guard let followed = relativeTarget(ofFieldAt: implementation), textRange.contains(followed) else { return nil }
        return followed
    }

    /// The target of a 32-bit relative pointer stored at the unslid `field`,
    /// or `nil` when it is zero.
    private func relativeTarget(ofFieldAt field: UInt64) -> UInt64? {
        guard let relative = table.memory.load(Int32.self, at: table.runtimeAddress(ofUnslid: field)), relative != 0 else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: field) &+ Int64(relative))
    }

    /// The `Mn` and `Tq` symbols at the descriptors the sources name, from
    /// the symbol table and the export trie.
    private func descriptorSymbols() -> [UInt64: String] {
        let sources = self.sources()
        let exportedNames = ExportedFunctionNames.of(table).namesByAddress
        lock.lock()
        defer { lock.unlock() }
        if let descriptorSymbolsStorage { return descriptorSymbolsStorage }
        var wanted = Set<UInt64>()
        for source in sources.values {
            switch source {
            case .typeFunction(_, let descriptorAddress, _):
                wanted.insert(descriptorAddress)
            case .method(let descriptorAddress):
                wanted.insert(descriptorAddress)
            }
        }
        var symbols: [UInt64: String] = [:]
        // The names the export trie gives share their storage with it.
        var stringByteCount = 0
        func consider(_ name: String, at address: UInt64) -> Bool {
            guard symbols[address] == nil, name.hasSuffix("Mn") || name.hasSuffix("Tq") else { return false }
            symbols[address] = name
            return true
        }
        let linkEdit = ImageLinkEdit(image: table.image, memory: table.memory)
        for symbolIndex in linkEdit.symbols.indices {
            let entry = linkEdit.symbols[symbolIndex]
            guard ImageLinkEdit.isDefinedInSection(entry), wanted.contains(entry.n_value), let symbolName = linkEdit.name(ofSymbolAt: symbolIndex) else { continue }
            let name = String(cString: symbolName)
            if consider(name, at: entry.n_value) { stringByteCount += ApproximateSize.of(name) }
        }
        for address in wanted {
            for name in exportedNames[address] ?? [] { _ = consider(name, at: address) }
        }
        descriptorSymbolsStorage = symbols
        sourceByteCount += stringByteCount + ApproximateSize.of(symbols)
        return symbols
    }
}
