import Foundation
import MachOKit

/// What the language layers say about runtime libraries and helpers, for
/// the core to apply without knowing any language.
package struct RuntimeLibraryRules: Sendable {
    /// Whether the image at a path is a runtime library, whose exported
    /// functions the layers recognize by name.
    package let isRuntimeLibrary: @Sendable (String) -> Bool
    /// Whether a symbol names a runtime helper: a function that only manages
    /// memory or values, hidden from results by default.
    package let isRuntimeHelperName: @Sendable (UnsafePointer<CChar>) -> Bool

    package init(isRuntimeLibrary: @escaping @Sendable (String) -> Bool, isRuntimeHelperName: @escaping @Sendable (UnsafePointer<CChar>) -> Bool) {
        self.isRuntimeLibrary = isRuntimeLibrary
        self.isRuntimeHelperName = isRuntimeHelperName
    }
}

/// The images an analyzer covers, where they lie in its address space, and
/// what it keeps per image: the language-free half of the analyzer.
///
/// For the in-process analyzer the images are the process's: every image of
/// the dyld shared cache — loaded or not, the whole cache is mapped into
/// every process — plus every image loaded outside the cache when the set
/// was made. Images loaded later need a new set.
///
/// Remembers the function table of every image it was asked to keep one for
/// for its own lifetime; a whole-image scan builds its table and drops it.
package final class CodeImageSet: @unchecked Sendable {
    /// Every image, shared cache first.
    package let images: [CodeImage]
    /// Each image's path, by position in ``images``: where dyld loaded it —
    /// for a shared cache image, its install name.
    package let imagePaths: [String]
    /// Where every read of image memory goes.
    package let memory: any CrossReferenceMemory
    /// What `memory` reads, when it refers to it without keeping it alive:
    /// a `FileCrossReferenceMemory`'s storage, kept for the set's lifetime.
    private let memoryOwner: AnyObject?
    package let rules: RuntimeLibraryRules
    /// The runtime libraries' helper functions; helpers the compiler emits
    /// into each image are in that image's function table.
    package let runtimeHelperLocations: Set<CodeLocation>

    package struct ImageAddressRange {
        package let start: UInt
        package let end: UInt
        package let imageIndex: Int
    }

    /// Each image's `__TEXT` segment in memory, sorted by start.
    package let textRanges: [ImageAddressRange]
    /// Each image's other segments in memory but `__LINKEDIT`, sorted by start:
    /// where its class objects and its GOT slots lie.
    package let dataRanges: [ImageAddressRange]
    /// The memory the shared cache maps executable — its images' code, and
    /// the stubs and islands the cache builder put between them.
    package let executableRanges: [Range<UInt>]
    /// Every mapping of the shared cache and every segment of the images
    /// outside it: what may be read without faulting.
    package let mappedRanges: [Range<UInt>]

    private let indicesByPath: [String: Int]
    /// Every image an install name names: the name load commands link an
    /// image by. Two copies of one framework, loaded from two places, share
    /// one.
    private let indicesByInstallName: [String: [Int]]
    private let lock = NSLock()
    private var functionTables: [Int: ImageFunctionTable] = [:]
    private var linkageStorage: Linkage?
    private var renamedReexportStorage: RenamedReexportIndex?
    /// Held while the renamed re-exports are built, so they are built once.
    private let renamedReexportBuildLock = NSLock()
    private var renamedReexportBuildCountStorage = 0

    /// The current process's images, or `nil` when it does not run arm64
    /// code.
    ///
    /// `visitRuntimeLibrarySymbol` sees every symbol the runtime libraries
    /// define, with where it lies, in the one pass over them the set makes
    /// to find their helpers: from their symbol tables, and from their export
    /// tries, since a cache image's symbol table need not hold its exported
    /// symbols. A name that both name may come twice.
    package static func inProcess(rules: RuntimeLibraryRules, visitingRuntimeLibrarySymbols visitRuntimeLibrarySymbol: (UnsafePointer<CChar>, CodeLocation) -> Void) -> CodeImageSet? {
        #if arch(arm64)
        var images: [MachOImage] = []
        var executableRanges: [Range<UInt>] = []
        var mappedRanges: [Range<UInt>] = []
        if let cache = DyldCacheLoaded.current, let slide = cache.slide {
            images.append(contentsOf: cache.machOImages())
            func appendMappings(of subcache: DyldCacheLoaded) {
                guard let mappings = subcache.mappingInfos else { return }
                for mapping in mappings {
                    let start = UInt(bitPattern: Int(bitPattern: UInt(mapping.layout.address)) &+ slide)
                    let range = start ..< start + UInt(mapping.layout.size)
                    mappedRanges.append(range)
                    if mapping.maxProtection.contains(.execute) { executableRanges.append(range) }
                }
            }
            appendMappings(of: cache)
            if let subCaches = cache.subCaches {
                for entry in subCaches {
                    if let subcache = try? entry.subcache(for: cache) { appendMappings(of: subcache) }
                }
            }
        }
        // Where dyld loaded each image outside the cache, read off the header
        // itself so that an image loaded or unloaded meanwhile cannot shift
        // it onto another.
        var loadedPaths: [Int: String] = [:]
        for imageIndex in 0 ..< _dyld_image_count() {
            guard let header = _dyld_get_image_header(imageIndex) else { continue }
            let image = MachOImage(ptr: header)
            guard !image.header.isInDyldCache else { continue }
            var information = Dl_info()
            if dladdr(UnsafeRawPointer(header), &information) != 0, let fileName = information.dli_fname {
                loadedPaths[images.count] = String(cString: fileName)
            }
            images.append(image)
        }
        let codeImages = images.enumerated().map { imageIndex, image in
            CodeImage(image: image, path: loadedPaths[imageIndex] ?? image.path ?? "")
        }
        return CodeImageSet(
            images: codeImages,
            executableRanges: executableRanges,
            mappedRanges: mappedRanges,
            memory: InProcessCrossReferenceMemory(),
            rules: rules,
            visitingRuntimeLibrarySymbols: visitRuntimeLibrarySymbol
        )
        #else
        return nil
        #endif
    }

    /// Every image of a dyld shared cache read from disk, at its own unslid
    /// addresses: what an archived cache, or another device's, is analyzed
    /// as. The images come in the cache's order — the order the in-process
    /// set lists the running cache's images in.
    package static func dyldCache(
        _ cache: FullDyldCache,
        rules: RuntimeLibraryRules,
        visitingRuntimeLibrarySymbols visitRuntimeLibrarySymbol: (UnsafePointer<CChar>, CodeLocation) -> Void
    ) -> CodeImageSet {
        var executableRanges: [Range<UInt>] = []
        var mappedRanges: [Range<UInt>] = []
        for subcache in cache.allCaches {
            for mapping in subcache.mappingInfos ?? [] {
                let start = UInt(mapping.layout.address)
                let range = start ..< start + UInt(mapping.layout.size)
                mappedRanges.append(range)
                if mapping.maxProtection.contains(.execute) { executableRanges.append(range) }
            }
        }
        let storage = FileCrossReferenceMemory.storage(cache: cache)
        return CodeImageSet(
            images: cache.machOFiles().map { CodeImage(file: $0) },
            executableRanges: executableRanges,
            mappedRanges: mappedRanges,
            memory: FileCrossReferenceMemory(storage: storage),
            memoryOwner: storage,
            rules: rules,
            visitingRuntimeLibrarySymbols: visitRuntimeLibrarySymbol
        )
    }

    /// Standalone Mach-O files — an app's executable and its frameworks —
    /// each placed where its address range overlaps no other's, as dyld
    /// would: a file overlapping one placed before it is slid to the next
    /// megabyte past every file placed so far. Most frameworks are linked at
    /// 0, so all but the first are slid.
    package static func files(
        _ files: [MachOFile],
        rules: RuntimeLibraryRules,
        visitingRuntimeLibrarySymbols visitRuntimeLibrarySymbol: (UnsafePointer<CChar>, CodeLocation) -> Void
    ) -> CodeImageSet {
        var placements: [(file: MachOFile, slide: Int)] = []
        var occupiedRanges: [Range<UInt64>] = []
        for file in files {
            let segments = file.segments64.filter { $0.layout.vmsize > 0 && $0.segmentName != "__PAGEZERO" }
            guard let lowest = segments.map({ UInt64($0.layout.vmaddr) }).min(),
                  let highest = segments.map({ UInt64($0.layout.vmaddr) &+ UInt64($0.layout.vmsize) }).max()
            else {
                placements.append((file, 0))
                continue
            }
            var slide = 0
            if occupiedRanges.contains(where: { $0.overlaps(lowest ..< highest) }), let occupiedEnd = occupiedRanges.map(\.upperBound).max() {
                let placedStart = (occupiedEnd &+ 0xF_FFFF) & ~UInt64(0xF_FFFF)
                slide = Int(truncatingIfNeeded: Int64(bitPattern: placedStart &- lowest))
            }
            let slidLowest = UInt64(bitPattern: Int64(bitPattern: lowest) &+ Int64(slide))
            occupiedRanges.append(slidLowest ..< slidLowest &+ (highest &- lowest))
            placements.append((file, slide))
        }
        let storage = FileCrossReferenceMemory.storage(files: placements)
        return CodeImageSet(
            images: placements.map { CodeImage(file: $0.file, slide: $0.slide) },
            executableRanges: [],
            mappedRanges: [],
            memory: FileCrossReferenceMemory(storage: storage),
            memoryOwner: storage,
            rules: rules,
            visitingRuntimeLibrarySymbols: visitRuntimeLibrarySymbol
        )
    }

    private init(
        images: [CodeImage],
        executableRanges: [Range<UInt>],
        mappedRanges: [Range<UInt>],
        memory: any CrossReferenceMemory,
        memoryOwner: AnyObject? = nil,
        rules: RuntimeLibraryRules,
        visitingRuntimeLibrarySymbols visitRuntimeLibrarySymbol: (UnsafePointer<CChar>, CodeLocation) -> Void
    ) {
        var executableRanges = executableRanges
        var mappedRanges = mappedRanges
        var imagePaths: [String] = []
        var indicesByPath: [String: Int] = [:]
        var indicesByInstallName: [String: [Int]] = [:]
        var textRanges: [ImageAddressRange] = []
        var dataRanges: [ImageAddressRange] = []
        for (imageIndex, image) in images.enumerated() {
            let path = image.path
            imagePaths.append(path)
            if indicesByPath[path] == nil { indicesByPath[path] = imageIndex }
            if let installName = image.installName { indicesByInstallName[installName, default: []].append(imageIndex) }
            let segments = Array(image.reader.segments64)
            guard let text = segments.first(where: { $0.segmentName == "__TEXT" }) else { continue }
            let start = image.runtimeAddress(ofUnslid: UInt64(text.layout.vmaddr))
            textRanges.append(ImageAddressRange(start: start, end: start + UInt(text.layout.vmsize), imageIndex: imageIndex))
            for segment in segments where segment.layout.vmsize > 0 && !["__TEXT", "__LINKEDIT", "__PAGEZERO"].contains(segment.segmentName) {
                let segmentStart = image.runtimeAddress(ofUnslid: UInt64(segment.layout.vmaddr))
                dataRanges.append(ImageAddressRange(start: segmentStart, end: segmentStart + UInt(segment.layout.vmsize), imageIndex: imageIndex))
            }
            if !image.isInSharedCache {
                executableRanges.append(start ..< start + UInt(text.layout.vmsize))
                for segment in segments where segment.layout.vmsize > 0 && segment.segmentName != "__PAGEZERO" {
                    let segmentStart = image.runtimeAddress(ofUnslid: UInt64(segment.layout.vmaddr))
                    mappedRanges.append(segmentStart ..< segmentStart + UInt(segment.layout.vmsize))
                }
            }
        }
        textRanges.sort { $0.start < $1.start }
        dataRanges.sort { $0.start < $1.start }

        self.images = images
        self.imagePaths = imagePaths
        self.indicesByPath = indicesByPath
        self.indicesByInstallName = indicesByInstallName
        self.textRanges = textRanges
        self.dataRanges = dataRanges
        self.executableRanges = executableRanges
        self.mappedRanges = mappedRanges
        self.memory = memory
        self.memoryOwner = memoryOwner
        self.rules = rules

        var runtimeHelperLocations = Set<CodeLocation>()
        Self.forEachDefinedSymbol(ofImagesMatching: rules.isRuntimeLibrary, images: images, memory: memory) { name, location in
            if rules.isRuntimeHelperName(name) { runtimeHelperLocations.insert(location) }
            visitRuntimeLibrarySymbol(name, location)
        }
        self.runtimeHelperLocations = runtimeHelperLocations
    }

    private static func forEachDefinedSymbol(
        ofImagesMatching isWanted: (String) -> Bool,
        images: [CodeImage],
        memory: any CrossReferenceMemory,
        _ body: (UnsafePointer<CChar>, CodeLocation) -> Void
    ) {
        for (imageIndex, image) in images.enumerated() where isWanted(image.path) {
            let linkEdit = ImageLinkEdit(image: image, memory: memory)
            for symbolIndex in linkEdit.symbols.indices {
                let entry = linkEdit.symbols[symbolIndex]
                guard ImageLinkEdit.isDefinedInSection(entry), let name = linkEdit.name(ofSymbolAt: symbolIndex) else { continue }
                body(name, CodeLocation(imageIndex: imageIndex, address: entry.n_value))
            }
            for symbol in image.reader.exportedSymbols {
                guard let offset = symbol.offset else { continue }
                symbol.name.withCString { body($0, CodeLocation(imageIndex: imageIndex, address: image.unslidAddress(atHeaderOffset: offset))) }
            }
        }
    }

    /// The tables of the image's `__LINKEDIT`, read from memory.
    package func linkEdit(ofImageAt imageIndex: Int) -> ImageLinkEdit {
        ImageLinkEdit(image: images[imageIndex], memory: memory)
    }

    package func isRuntimeHelperName(_ name: UnsafePointer<CChar>) -> Bool {
        rules.isRuntimeHelperName(name)
    }

    // MARK: - Images and addresses

    /// The position in ``images`` of the image at `path`: where dyld loaded
    /// it, which for a shared cache image is its install name. An install
    /// name finds an image outside the cache too.
    package func imageIndex(forPath path: String) -> Int? {
        indicesByPath[path] ?? indicesByInstallName[path]?.first
    }

    /// The image whose `__TEXT` segment holds the runtime address `address`,
    /// and the unslid address there.
    package func location(ofRuntimeAddress address: UInt) -> CodeLocation? {
        guard let imageIndex = imageIndex(containingRuntimeAddress: address) else { return nil }
        return CodeLocation(imageIndex: imageIndex, address: images[imageIndex].unslidAddress(ofRuntime: address))
    }

    /// What to add to an unslid address of the image at `imageIndex` to reach
    /// the analyzer's address space.
    package func slide(ofImageAt imageIndex: Int) -> Int {
        images[imageIndex].slide
    }

    /// The runtime address of `location`.
    package func runtimeAddress(of location: CodeLocation) -> UInt {
        images[location.imageIndex].runtimeAddress(ofUnslid: location.address)
    }

    package func imageIndex(containingRuntimeAddress address: UInt) -> Int? {
        Self.imageIndex(containing: address, in: textRanges)
    }

    /// The image whose segments other than `__TEXT` hold the runtime
    /// `address`.
    package func imageIndex(containingDataAddress address: UInt) -> Int? {
        Self.imageIndex(containing: address, in: dataRanges)
    }

    private static func imageIndex(containing address: UInt, in ranges: [ImageAddressRange]) -> Int? {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if ranges[middle].start <= address { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let candidate = ranges[lower - 1]
        return address < candidate.end ? candidate.imageIndex : nil
    }

    /// Whether `length` bytes at the runtime `address` are mapped executable.
    package func isExecutable(runtimeAddress address: UInt, length: UInt) -> Bool {
        let (end, overflow) = address.addingReportingOverflow(length)
        guard !overflow else { return false }
        return executableRanges.contains { $0.lowerBound <= address && end <= $0.upperBound }
    }

    /// Whether `length` bytes at the runtime `address` are mapped at all.
    package func isMapped(runtimeAddress address: UInt, length: UInt) -> Bool {
        let (end, overflow) = address.addingReportingOverflow(length)
        guard !overflow else { return false }
        return mappedRanges.contains { $0.lowerBound <= address && end <= $0.upperBound }
    }

    /// How many bytes from the runtime `address` on may be read: up to the
    /// end of the mapping that holds it, or none.
    package func mappedLength(fromRuntimeAddress address: UInt) -> UInt {
        guard let range = mappedRanges.first(where: { $0.contains(address) }) else { return 0 }
        return range.upperBound - address
    }

    /// Whether the runtime `address` is a slot of the GOT pool the shared
    /// cache keeps outside every image: mapped, and in no image's segments.
    package func isSlotOutsideEveryImage(runtimeAddress address: UInt) -> Bool {
        imageIndex(containingDataAddress: address) == nil
            && imageIndex(containingRuntimeAddress: address) == nil
            && isMapped(runtimeAddress: address, length: 8)
    }

    // MARK: - Function tables

    /// The image's function table, built on first use and then kept for the
    /// set's lifetime — what naming functions needs.
    package func functionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable {
        lock.lock()
        if let table = functionTables[imageIndex] {
            lock.unlock()
            return table
        }
        lock.unlock()
        // Built outside the lock: two threads may build the same table once
        // each, and the first one stored wins.
        let table = makeFunctionTable(ofImageAt: imageIndex)
        lock.lock()
        defer { lock.unlock() }
        if let stored = functionTables[imageIndex] { return stored }
        functionTables[imageIndex] = table
        return table
    }

    /// The table the set keeps for the image, or a new one it does not keep:
    /// for a scan of a whole image, which would otherwise keep every table a
    /// cross-image query touched.
    package func transientFunctionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable {
        existingFunctionTable(ofImageAt: imageIndex) ?? makeFunctionTable(ofImageAt: imageIndex)
    }

    package func existingFunctionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable? {
        lock.lock()
        defer { lock.unlock() }
        return functionTables[imageIndex]
    }

    private func makeFunctionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable {
        ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex], linkEdit: linkEdit(ofImageAt: imageIndex), memory: memory, isRuntimeHelperName: rules.isRuntimeHelperName)
    }

    /// Drops the function tables of every image but `keptImageIndices`, and
    /// returns them so that the caller frees them outside any lock.
    package func releaseFunctionTables(exceptForImagesAt keptImageIndices: Set<Int>) -> [Int: ImageFunctionTable] {
        lock.lock()
        defer { lock.unlock() }
        let released = functionTables
        functionTables = functionTables.filter { keptImageIndices.contains($0.key) }
        return released
    }

    // MARK: - Linkage

    /// Whether the linkage and the renamed re-exports are read; for tests.
    package var hasPreparedPrefilters: Bool {
        lock.lock()
        defer { lock.unlock() }
        return linkageStorage != nil && renamedReexportStorage != nil
    }

    /// Built on first use and kept: reading every image's load commands takes
    /// a few tens of milliseconds.
    package func linkage() -> Linkage {
        lock.lock()
        if let linkageStorage {
            lock.unlock()
            return linkageStorage
        }
        lock.unlock()
        var dependents: [Int: [Int]] = [:]
        var reexporters: [Int: [Int]] = [:]
        var executables: [Int] = []
        var bundles: [Int] = []
        for (imageIndex, image) in images.enumerated() {
            switch image.reader.header.fileType {
            case .execute?: executables.append(imageIndex)
            case .bundle?: bundles.append(imageIndex)
            default: break
            }
            for (name, isReexport) in linkedDylibs(ofImageAt: imageIndex) {
                for dependency in imageIndices(linkedAs: name) where dependency != imageIndex {
                    dependents[dependency, default: []].append(imageIndex)
                    if isReexport { reexporters[dependency, default: []].append(imageIndex) }
                }
            }
        }
        // A bundle linked with `-bundle_loader` binds to the main executable,
        // which no load command names; every bundle counts as linking it.
        for executable in executables {
            dependents[executable, default: []].append(contentsOf: bundles)
        }
        let linkage = Linkage(dependents: dependents, reexporters: reexporters)
        lock.lock()
        defer { lock.unlock() }
        if let linkageStorage { return linkageStorage }
        linkageStorage = linkage
        return linkage
    }

    /// The names of the dylibs the image's load commands link, in order —
    /// the order a bind's or a re-export's library ordinal counts, from 1 —
    /// and whether each is re-exported.
    private func linkedDylibs(ofImageAt imageIndex: Int) -> [(name: String, isReexport: Bool)] {
        images[imageIndex].reader.dependencies.map { ($0.dylib.name, $0.type == .reexport) }
    }

    /// The images a load command's dylib name stands for: every image with
    /// that install name, or the image loaded from that path.
    private func imageIndices(linkedAs name: String) -> [Int] {
        indicesByInstallName[name] ?? indicesByPath[name].map { [$0] } ?? []
    }

    /// The images the image at `imageIndex` links, by library ordinal: the
    /// first element for ordinal 1. An element is empty when no image the
    /// set knows is that dylib.
    package func dependencyImageIndices(ofImageAt imageIndex: Int) -> [[Int]] {
        linkedDylibs(ofImageAt: imageIndex).map { imageIndices(linkedAs: $0.name) }
    }

    /// Built on first use and kept: every image's export trie is walked once,
    /// and what is kept is small. Built once: a caller that asks while it is
    /// being built waits for it.
    package func renamedReexports(concurrently: Bool = true) -> RenamedReexportIndex {
        lock.lock()
        if let renamedReexportStorage {
            lock.unlock()
            return renamedReexportStorage
        }
        lock.unlock()
        renamedReexportBuildLock.lock()
        defer { renamedReexportBuildLock.unlock() }
        lock.lock()
        if let renamedReexportStorage {
            lock.unlock()
            return renamedReexportStorage
        }
        lock.unlock()
        let index = RenamedReexportIndex(images: self, concurrently: concurrently)
        lock.lock()
        renamedReexportStorage = index
        renamedReexportBuildCountStorage += 1
        lock.unlock()
        return index
    }

    /// How many times the renamed re-exports were built; for tests.
    package var renamedReexportBuildCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return renamedReexportBuildCountStorage
    }
}
