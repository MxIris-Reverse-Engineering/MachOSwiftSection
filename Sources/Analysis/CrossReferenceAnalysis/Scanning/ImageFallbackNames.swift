import Foundation
import MachOKit
import MachOObjCSection
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Names for the functions an image's symbol table leaves unnamed: from the
/// export trie, the Objective-C method lists, and the Swift metadata — tried
/// in that order, each read only when a function is still unnamed after the
/// ones before it.
///
/// Read when a function is named, never during a scan. A scan needs no names,
/// and reading an image's method lists and metadata costs about as much as
/// scanning it (AppKit's method lists alone take 42–86 ms). Evolution proposal
/// `cross-reference-analysis`, batch two.
final class ImageFallbackNames: @unchecked Sendable {
    struct ObjectiveCMethod {
        let className: String
        let selector: String
        let isClassMethod: Bool
    }

    /// Where a Swift function's name comes from.
    private enum SwiftSource {
        /// A type's metadata accessor (`Ma`) or singleton completion function
        /// (`Mr`): the type's descriptor, and the suffix the name ends in.
        case typeFunction(descriptor: TypeContextDescriptorWrapper, suffix: String)
        /// A method whose descriptor's `…Tq` symbol spells its name.
        case method(descriptorAddress: UInt64)
    }

    private let image: MachOImage
    private let headerAddress: UInt64
    private let slide: Int
    private let textRange: Range<UInt64>

    private let lock = NSLock()
    private var exportedNamesStorage: [UInt64: [String]]?
    private var objectiveCMethodsStorage: [UInt64: ObjectiveCMethod]?
    private var swiftSourcesStorage: [UInt64: SwiftSource]?
    /// The `Mn` / `Tq` symbol at each descriptor the Swift sources name.
    private var descriptorSymbolsStorage: [UInt64: String]?
    private var swiftNames: [UInt64: String?] = [:]
    /// What the sources read so far take, counted as each is read.
    private var sourceByteCount = 0

    init(image: MachOImage, headerAddress: UInt64, slide: Int, textRange: Range<UInt64>) {
        self.image = image
        self.headerAddress = headerAddress
        self.slide = slide
        self.textRange = textRange
    }

    /// The name of the function at the unslid `address`, and the other names
    /// at the same address, when one of the sources has one.
    func name(at address: UInt64) -> (name: CodeFunction.Name, foldedSymbolNames: [String])? {
        if let names = exportedNames()[address], let first = names.first {
            return (.symbol(first), Array(names.dropFirst()))
        }
        if let method = objectiveCMethods()[address] {
            return (.objectiveCMethod(className: method.className, selector: method.selector, isClassMethod: method.isClassMethod), [])
        }
        if let mangledName = swiftName(at: address) {
            return (.swiftMetadata(mangledName: mangledName), [])
        }
        return nil
    }

    /// Reads every source now — for a host that will name functions of the
    /// image and wants none of it read while it waits. Each function's Swift
    /// name is still rebuilt the first time it is asked for.
    func readEverySource() {
        _ = objectiveCMethods()
        // Reads the export trie and the Swift metadata on its way.
        _ = descriptorSymbols()
    }

    /// Whether every source has been read; for tests.
    var hasReadEverySource: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exportedNamesStorage != nil && objectiveCMethodsStorage != nil && swiftSourcesStorage != nil && descriptorSymbolsStorage != nil
    }

    /// The memory the sources read so far and the Swift names rebuilt take;
    /// see `ApproximateSize`.
    var approximateByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return swiftNames.values.reduce(sourceByteCount + ApproximateSize.of(swiftNames)) { $0 + ($1.map(ApproximateSize.of) ?? 0) }
    }

    // MARK: - Export trie

    /// What the export trie names, by address: functions in `__text`, and the
    /// descriptors in `__TEXT,__const` whose symbols name Swift functions. A
    /// shared cache image's symbol table may hold its local symbols alone
    /// (SiriAppIntents' holds two entries; its export trie names 76,318
    /// functions), and an iOS device's cache redacts the local ones while the
    /// export trie survives.
    private func exportedNames() -> [UInt64: [String]] {
        lock.lock()
        defer { lock.unlock() }
        if let exportedNamesStorage { return exportedNamesStorage }
        var names: [UInt64: [String]] = [:]
        var byteCount = 0
        for symbol in image.exportedSymbols {
            guard let offset = symbol.offset else { continue }
            names[address(atOffset: offset), default: []].append(symbol.name)
            byteCount += ApproximateSize.of(symbol.name)
        }
        exportedNamesStorage = names
        sourceByteCount += names.values.reduce(byteCount + ApproximateSize.of(names)) { $0 + ApproximateSize.of($1) }
        return names
    }

    // MARK: - Objective-C

    /// Every method implementation the image's own class and category lists
    /// name. A shared cache attaches other images' category lists to a
    /// class's list of lists; those are skipped, because the image that holds
    /// them lists the same methods in its own `__objc_catlist`.
    func objectiveCMethods() -> [UInt64: ObjectiveCMethod] {
        lock.lock()
        defer { lock.unlock() }
        if let objectiveCMethodsStorage { return objectiveCMethodsStorage }
        var methods: [UInt64: ObjectiveCMethod] = [:]
        // A class's methods share its name's storage.
        var stringByteCount = 0

        func record(_ methodList: ObjCMethodList, in listImage: MachOImage, className: String, isClassMethod: Bool) {
            guard !methodList.isListOfLists else { return }
            for method in methodList.methods(in: listImage) where method.imp != 0 {
                let address = unslidAddress(ofRuntime: method.imp)
                guard textRange.contains(address), methods[address] == nil else { continue }
                methods[address] = ObjectiveCMethod(className: className, selector: method.name, isClassMethod: isClassMethod)
                stringByteCount += ApproximateSize.of(method.name)
            }
        }

        func ownLists(of readOnlyData: ObjCClassROData64, in owner: MachOImage) -> [(MachOImage, ObjCMethodList)] {
            if let methodList = readOnlyData.methodList(in: owner) { return [(owner, methodList)] }
            guard let listOfLists = readOnlyData.methodRelativeListList(in: owner) else { return [] }
            return listOfLists.lists(in: owner).filter { $0.0.ptr == image.ptr }
        }

        for classObject in image.objc.classes64 ?? [] {
            guard let readOnlyData = ObjectiveCClassIndex.readOnlyData(of: classObject, in: image),
                  let className = readOnlyData.name(in: image)
            else { continue }
            stringByteCount += ApproximateSize.of(className)
            for (listImage, methodList) in ownLists(of: readOnlyData, in: image) {
                record(methodList, in: listImage, className: className, isClassMethod: false)
            }
            if let (metaImage, metaClass) = classObject.metaClass(in: image),
               let metaReadOnlyData = ObjectiveCClassIndex.readOnlyData(of: metaClass, in: metaImage) {
                for (listImage, methodList) in ownLists(of: metaReadOnlyData, in: metaImage) {
                    record(methodList, in: listImage, className: className, isClassMethod: true)
                }
            }
        }
        for category in (image.objc.categories64 ?? []) + (image.objc.categories2_64 ?? []) {
            guard let className = category.className(in: image), !className.isEmpty else { continue }
            stringByteCount += ApproximateSize.of(className)
            if let methodList = category.instanceMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: false)
            }
            if let methodList = category.classMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: true)
            }
        }
        objectiveCMethodsStorage = methods
        sourceByteCount += stringByteCount + ApproximateSize.of(methods)
        return methods
    }

    // MARK: - Swift

    /// The Swift name of the function at `address`, rebuilt from the
    /// metadata that points at it — remembered, since rebuilding a type's
    /// name without its `Mn` symbol takes a demangle and a remangle.
    func swiftName(at address: UInt64) -> String? {
        guard let source = swiftSources()[address] else { return nil }
        lock.lock()
        if let known = swiftNames[address] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let name = buildSwiftName(from: source)
        lock.lock()
        defer { lock.unlock() }
        swiftNames[address] = name
        return name
    }

    private func buildSwiftName(from source: SwiftSource) -> String? {
        let descriptorSymbols = self.descriptorSymbols()
        switch source {
        case .typeFunction(let descriptor, let suffix):
            let descriptorAddress = address(atOffset: descriptor.typeContextDescriptor.offset)
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
        guard let contextNode = try? SymbolicDemangler.demangleContext(for: descriptor.asContextDescriptorWrapper, in: image.context) else { return nil }
        return try? mangleAsString(NodeBuilder(kind: .type, children: [contextNode]).node)
    }

    /// Which functions the metadata names, by address: every type's
    /// metadata accessor and singleton completion function, and every
    /// vtable implementation.
    private func swiftSources() -> [UInt64: SwiftSource] {
        lock.lock()
        defer { lock.unlock() }
        if let swiftSourcesStorage { return swiftSourcesStorage }
        var sources: [UInt64: SwiftSource] = [:]
        let context = image.context
        for wrapper in (try? image.swift.typeContextDescriptors) ?? [] {
            let descriptorOffset = wrapper.typeContextDescriptor.offset
            // Every type context descriptor holds its metadata accessor as a
            // relative direct pointer at +12.
            let accessorField = address(atOffset: descriptorOffset) &+ 12
            if let accessor = relativeTarget(ofFieldAt: accessorField), textRange.contains(accessor) {
                sources[accessor] = .typeFunction(descriptor: wrapper, suffix: "Ma")
            }
            guard let typeWrapper = try? TypeContextWrapper.forTypeContextDescriptorWrapper(wrapper, in: context) else { continue }
            var completionOffset: Int?
            switch typeWrapper {
            case .class(let classType):
                completionOffset = classType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
                for method in classType.methodDescriptors {
                    guard let implementationOffset = method.implementationOffset,
                          let implementation = codeAddress(ofImplementationAtOffset: implementationOffset),
                          sources[implementation] == nil
                    else { continue }
                    sources[implementation] = .method(descriptorAddress: address(atOffset: method.offset))
                }
            case .struct(let structType):
                completionOffset = structType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
            case .enum(let enumType):
                completionOffset = enumType.singletonMetadataInitialization?.resolvedDirectOffset(from: \.completionFunction)
            }
            if let completionOffset {
                let completion = address(atOffset: completionOffset)
                if textRange.contains(completion) {
                    sources[completion] = .typeFunction(descriptor: wrapper, suffix: "Mr")
                }
            }
        }
        swiftSourcesStorage = sources
        sourceByteCount += ApproximateSize.of(sources)
        return sources
    }

    /// An implementation's code: the offset itself when it lies in `__text`,
    /// or — for an async function — the function an async function pointer
    /// record (`{ rel32 function, u32 context size }`) leads to.
    private func codeAddress(ofImplementationAtOffset offset: Int) -> UInt64? {
        let implementation = address(atOffset: offset)
        if textRange.contains(implementation) { return implementation }
        guard let followed = relativeTarget(ofFieldAt: implementation), textRange.contains(followed) else { return nil }
        return followed
    }

    /// The target of a 32-bit relative pointer stored at the unslid `field`,
    /// or `nil` when it is zero.
    private func relativeTarget(ofFieldAt field: UInt64) -> UInt64? {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(field)) &+ slide) else { return nil }
        let relative = pointer.loadUnaligned(as: Int32.self)
        guard relative != 0 else { return nil }
        return UInt64(bitPattern: Int64(bitPattern: field) &+ Int64(relative))
    }

    /// The `Mn` and `Tq` symbols at the descriptors the Swift sources name,
    /// from the symbol table and the export trie.
    private func descriptorSymbols() -> [UInt64: String] {
        let sources = swiftSources()
        let exportedNames = self.exportedNames()
        lock.lock()
        defer { lock.unlock() }
        if let descriptorSymbolsStorage { return descriptorSymbolsStorage }
        var wanted = Set<UInt64>()
        for source in sources.values {
            switch source {
            case .typeFunction(let descriptor, _):
                wanted.insert(address(atOffset: descriptor.typeContextDescriptor.offset))
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
        if let symbolTable = image.symbols64 {
            for symbolIndex in 0 ..< symbolTable.numberOfSymbols {
                let entry = symbolTable.symbols[symbolIndex]
                // Defined in a section, not a debugging entry.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E, wanted.contains(entry.n_value) else { continue }
                let name = String(cString: symbolTable.stringBase.advanced(by: Int(entry.n_un.n_strx)))
                if consider(name, at: entry.n_value) { stringByteCount += ApproximateSize.of(name) }
            }
        }
        for address in wanted {
            for name in exportedNames[address] ?? [] { _ = consider(name, at: address) }
        }
        descriptorSymbolsStorage = symbols
        sourceByteCount += stringByteCount + ApproximateSize.of(symbols)
        return symbols
    }

    private func unslidAddress(ofRuntime runtimeAddress: UInt64) -> UInt64 {
        // Strip the pointer-authentication bits; user addresses fit in 47.
        let address = runtimeAddress & 0x0000_7FFF_FFFF_FFFF
        return UInt64(bitPattern: Int64(bitPattern: address) &- Int64(slide))
    }
}

extension ImageFallbackNames {
    /// The unslid address `offset` bytes from the Mach header. Offsets may be
    /// negative: in a shared cache, an export or an implementation can lie
    /// below the image's own header.
    fileprivate func address(atOffset offset: Int) -> UInt64 {
        UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset))
    }
}
