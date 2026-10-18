import Foundation
import MachOKit

/// Reads what each function of an image references, from its arm64 machine
/// code, inside the current process.
///
/// An analyzer is a snapshot of the process's code: every image of the dyld
/// shared cache — loaded or not, the whole cache is mapped into every
/// process — plus every image loaded outside the cache when the analyzer was
/// made. Images loaded later need a new analyzer.
///
/// An analyzer remembers the function table of every image it was asked to
/// name functions in (``functions(inImageAt:)``, ``function(containing:)``,
/// ``references(madeBy:)``) for its own lifetime; a whole-image scan builds
/// its table and drops it. It keeps no reference results either:
/// ``referenceTable(ofImageAt:)`` returns a value the host holds for as long
/// as it wants. Drop the analyzer to release the function tables.
///
/// Only arm64 and arm64e are read. Evolution proposal
/// `cross-reference-analysis`.
public final class CrossReferenceAnalyzer: @unchecked Sendable {
    /// Every image the analyzer knows, shared cache first.
    public let images: [MachOImage]
    /// Each image's path, by position in ``images``: where dyld loaded it —
    /// for a shared cache image, its install name.
    ///
    /// Not the install name for an image outside the cache: an app's main
    /// executable and its bundles have none, and its frameworks have an
    /// `@rpath/…` one, which names no file.
    public let imagePaths: [String]

    struct ImageAddressRange {
        let start: UInt
        let end: UInt
        let imageIndex: Int
    }

    /// Each image's `__TEXT` segment in memory, sorted by start.
    let textRanges: [ImageAddressRange]
    /// Each image's other segments in memory but `__LINKEDIT`, sorted by start:
    /// where its class objects and its GOT slots lie.
    let dataRanges: [ImageAddressRange]
    /// The memory the shared cache maps executable — its images' code, and
    /// the stubs and islands the cache builder put between them.
    let executableRanges: [Range<UInt>]
    /// Every mapping of the shared cache and every segment of the images
    /// outside it: what may be read without faulting.
    let mappedRanges: [Range<UInt>]
    /// Where `objc_msgSend` lives, the original and the copies the cache
    /// carries for its shared selector stubs.
    let messageSendLocations: Set<CodeLocation>
    let superMessageSendLocations: Set<CodeLocation>
    /// The runtime libraries' helper functions; helpers the compiler emits
    /// into each image are in that image's function table.
    let runtimeHelperLocations: Set<CodeLocation>
    /// `objc_opt_self`, `objc_opt_class` and `swift_getInitializedObjCClass`:
    /// each returns the class it was handed, so `x0` keeps naming it.
    let classReturningFunctionLocations: Set<CodeLocation>
    /// The runtime's entry points that instantiate a type from its mangled
    /// name, and the register each takes the name in: `x0`, or `x1` for the
    /// `…InMetadataState` forms, whose first argument is the state.
    let typeByMangledNameEntries: [CodeLocation: Int]

    private let indicesByPath: [String: Int]
    /// Every image an install name names: the name load commands link an
    /// image by. Two copies of one framework, loaded from two places, share
    /// one.
    private let indicesByInstallName: [String: [Int]]
    private let lock = NSLock()
    private var functionTables: [Int: ImageFunctionTable] = [:]
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]
    private var swiftTypeIndexes: [Int: SwiftTypeIndex] = [:]
    private var linkageStorage: Linkage?
    private var renamedReexportStorage: RenamedReexportIndex?
    /// Held while the renamed re-exports are built, so they are built once.
    private let renamedReexportBuildLock = NSLock()
    private var renamedReexportBuildCountStorage = 0

    /// The analyzer for the current process, or `nil` when it does not run
    /// arm64 code.
    public init?() {
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

        var imagePaths: [String] = []
        var indicesByPath: [String: Int] = [:]
        var indicesByInstallName: [String: [Int]] = [:]
        var textRanges: [ImageAddressRange] = []
        var dataRanges: [ImageAddressRange] = []
        for (imageIndex, image) in images.enumerated() {
            let installName = image.path
            let path = loadedPaths[imageIndex] ?? installName ?? ""
            imagePaths.append(path)
            if indicesByPath[path] == nil { indicesByPath[path] = imageIndex }
            if let installName { indicesByInstallName[installName, default: []].append(imageIndex) }
            guard let slide = image.vmaddrSlide, let text = image.segments64.first(where: { $0.segmentName == "__TEXT" }) else { continue }
            let start = UInt(bitPattern: Int(bitPattern: UInt(text.layout.vmaddr)) &+ slide)
            textRanges.append(ImageAddressRange(start: start, end: start + UInt(text.layout.vmsize), imageIndex: imageIndex))
            for segment in image.segments64 where segment.layout.vmsize > 0 && !["__TEXT", "__LINKEDIT", "__PAGEZERO"].contains(segment.segmentName) {
                let segmentStart = UInt(bitPattern: Int(bitPattern: UInt(segment.layout.vmaddr)) &+ slide)
                dataRanges.append(ImageAddressRange(start: segmentStart, end: segmentStart + UInt(segment.layout.vmsize), imageIndex: imageIndex))
            }
            if !image.header.isInDyldCache {
                executableRanges.append(start ..< start + UInt(text.layout.vmsize))
                for segment in image.segments64 where segment.layout.vmsize > 0 && segment.segmentName != "__PAGEZERO" {
                    let segmentStart = UInt(bitPattern: Int(bitPattern: UInt(segment.layout.vmaddr)) &+ slide)
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

        // The runtime's entry points, found by name in the runtime libraries.
        var messageSendLocations = Set<CodeLocation>()
        var superMessageSendLocations = Set<CodeLocation>()
        var runtimeHelperLocations = Set<CodeLocation>()
        var classReturningFunctionLocations = Set<CodeLocation>()
        var typeByMangledNameEntries: [CodeLocation: Int] = [:]
        for (imageIndex, path) in imagePaths.enumerated() where Self.isRuntimeLibrary(path) {
            func classify(_ name: UnsafePointer<CChar>, at location: CodeLocation) {
                if strcmp(name, "_objc_msgSend") == 0 {
                    messageSendLocations.insert(location)
                } else if strcmp(name, "_objc_msgSendSuper2") == 0 {
                    superMessageSendLocations.insert(location)
                } else if strcmp(name, "_objc_opt_self") == 0 || strcmp(name, "_objc_opt_class") == 0 || strcmp(name, "_swift_getInitializedObjCClass") == 0 {
                    classReturningFunctionLocations.insert(location)
                } else if strncmp(name, "_swift_getTypeByMangledNameIn", 29) == 0 {
                    typeByMangledNameEntries[location] = strstr(name, "InMetadataState") == nil ? 0 : 1
                } else if RuntimeHelperNames.isRuntimeHelper(name) {
                    runtimeHelperLocations.insert(location)
                }
            }
            if let symbols = images[imageIndex].symbols64 {
                for symbolIndex in 0 ..< symbols.numberOfSymbols {
                    let entry = symbols.symbols[symbolIndex]
                    guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E else { continue }
                    classify(symbols.stringBase.advanced(by: Int(entry.n_un.n_strx)), at: CodeLocation(imageIndex: imageIndex, address: entry.n_value))
                }
            }
            // A cache image's symbol table need not hold its exported
            // symbols; the export trie always does.
            guard let headerAddress = images[imageIndex].segments64.first(where: { $0.segmentName == "__TEXT" }).map({ UInt64($0.layout.vmaddr) }) else { continue }
            for symbol in images[imageIndex].exportedSymbols {
                guard let offset = symbol.offset else { continue }
                symbol.name.withCString { classify($0, at: CodeLocation(imageIndex: imageIndex, address: UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset)))) }
            }
        }
        self.messageSendLocations = messageSendLocations
        self.superMessageSendLocations = superMessageSendLocations
        self.runtimeHelperLocations = runtimeHelperLocations
        self.classReturningFunctionLocations = classReturningFunctionLocations
        self.typeByMangledNameEntries = typeByMangledNameEntries
        #else
        return nil
        #endif
    }

    /// The libraries whose exported helpers a scan recognizes, and whose
    /// `objc_msgSend` copies the shared selector stubs branch to.
    private static func isRuntimeLibrary(_ path: String) -> Bool {
        path.hasSuffix("/libobjc.A.dylib")
            || path.hasSuffix("/libswiftCore.dylib")
            || path.hasSuffix("/libswift_Concurrency.dylib")
            || path.contains("/libobjcMsgSend")
    }

    // MARK: - Images and functions

    /// The position in ``images`` of the image at `path`: where dyld loaded
    /// it, which for a shared cache image is its install name. An install
    /// name finds an image outside the cache too.
    public func imageIndex(forPath path: String) -> Int? {
        indicesByPath[path] ?? indicesByInstallName[path]?.first
    }

    /// The image whose `__TEXT` segment holds the runtime address `address`,
    /// and the unslid address there.
    public func location(ofRuntimeAddress address: UInt) -> CodeLocation? {
        guard let imageIndex = imageIndex(containingRuntimeAddress: address),
              let slide = images[imageIndex].vmaddrSlide
        else { return nil }
        return CodeLocation(imageIndex: imageIndex, address: UInt64(bitPattern: Int64(Int(bitPattern: address) &- slide)))
    }

    /// Every function of the image, sorted by address.
    public func functions(inImageAt imageIndex: Int) -> [CodeFunction] {
        let table = functionTable(ofImageAt: imageIndex)
        return table.starts.indices.map { table.codeFunction(at: $0) }
    }

    /// The function whose code holds `location`.
    public func function(containing location: CodeLocation) -> CodeFunction? {
        let table = functionTable(ofImageAt: location.imageIndex)
        guard let index = table.functionIndex(containing: location.address) else { return nil }
        return table.codeFunction(at: index)
    }

    /// The functions holding each of `locations`, keyed by the location
    /// asked about — for naming the results of a query that touched many
    /// images. Each image's table is built for the lookup and dropped,
    /// unless the analyzer already holds it; a location in no function is
    /// left out.
    public func functions(containing locations: some Sequence<CodeLocation>) -> [CodeLocation: CodeFunction] {
        var functions: [CodeLocation: CodeFunction] = [:]
        for (imageIndex, imageLocations) in Dictionary(grouping: locations, by: \.imageIndex) {
            let table = existingFunctionTable(ofImageAt: imageIndex) ?? ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex])
            for location in imageLocations {
                guard let index = table.functionIndex(containing: location.address) else { continue }
                functions[location] = table.codeFunction(at: index)
            }
        }
        return functions
    }

    /// The symbol at exactly `location`, when one is there.
    public func symbolName(at location: CodeLocation) -> String? {
        guard let function = function(containing: location), function.location == location,
              case .symbol(let name)? = function.name
        else { return nil }
        return name
    }

    // MARK: - References

    /// What `function` references, in instruction order.
    public func references(madeBy function: CodeFunction) -> [CodeReference] {
        let table = functionTable(ofImageAt: function.location.imageIndex)
        guard let index = table.functionIndex(containing: function.location.address) else { return [] }
        var scanner = ReferenceScanner(analyzer: self, table: table)
        var references: [CodeReference] = []
        scanner.scanFunction(at: index, into: &references)
        return references
    }

    /// What every function of the image references, grouped by what it
    /// references.
    ///
    /// The image's function table is built for the scan and dropped after
    /// it, unless the analyzer already holds it: a cross-image query scans
    /// thousands of images, and keeping every table it touched held 1.5 GB
    /// after a scan of a macOS 27.2 cache.
    public func referenceTable(ofImageAt imageIndex: Int) -> CodeReferenceTable {
        let table = existingFunctionTable(ofImageAt: imageIndex) ?? ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex])
        var scanner = ReferenceScanner(analyzer: self, table: table)
        var references: [CodeReference] = []
        for index in table.starts.indices {
            scanner.scanFunction(at: index, into: &references)
        }
        return CodeReferenceTable(imageIndex: imageIndex, references: references)
    }

    /// Scans every function of the image once and files what a query for
    /// callers or for a type's references reads in a ``CodeReferenceIndex``:
    /// a quarter to a third of the memory of a ``CodeReferenceTable`` —
    /// AppKit's is 21 MiB against 67 MiB on macOS 27.2 — so a host can keep
    /// one for each image it has open and answer later queries without
    /// scanning again.
    ///
    /// Keeps the image's function table, which naming what the index answers
    /// needs: build indexes for the images a host means to keep, not for
    /// every image a cross-image query touches.
    public func referenceIndex(ofImageAt imageIndex: Int) -> CodeReferenceIndex {
        // Never stopped: the progress closure is absent.
        referenceIndex(ofImageAt: imageIndex, reportingProgress: nil)!
    }

    /// ``referenceIndex(ofImageAt:)``, telling `reportProgress` how many of
    /// the image's functions are scanned every so often, the last time when
    /// all are; it returns whether to go on, and the index is `nil` when it
    /// said not to.
    public func referenceIndex(
        ofImageAt imageIndex: Int,
        reportingProgress reportProgress: ((_ scannedFunctionCount: Int, _ functionCount: Int) -> Bool)?
    ) -> CodeReferenceIndex? {
        let table = functionTable(ofImageAt: imageIndex)
        var scanner = ReferenceScanner(analyzer: self, table: table)
        var builder = CodeReferenceIndex.Builder(imageIndex: imageIndex, codeStart: table.textStart)
        var functionReferences: [CodeReference] = []
        let functionCount = table.starts.count
        for index in table.starts.indices {
            if let reportProgress, index % Self.referenceIndexProgressStride == 0, !reportProgress(index, functionCount) {
                return nil
            }
            functionReferences.removeAll(keepingCapacity: true)
            scanner.scanFunction(at: index, into: &functionReferences)
            for reference in functionReferences {
                builder.add(reference)
            }
        }
        if let reportProgress, !reportProgress(functionCount, functionCount) {
            return nil
        }
        return builder.index()
    }

    /// How many functions an index's scan gets through between progress
    /// reports: a few dozen reports for a large image.
    static let referenceIndexProgressStride = 2048

    /// Builds the image's function table now, unless the analyzer holds it,
    /// and keeps it for the analyzer's lifetime — for a host about to name the
    /// functions a ``CodeReferenceIndex`` answers with, again and again, with
    /// an analyzer other than the one that built the index.
    public func keepFunctionTable(ofImageAt imageIndex: Int) {
        _ = functionTable(ofImageAt: imageIndex)
    }

    /// Reads now every name a query reads the first time it names a function
    /// of the image or looks up a class or a Swift type it defines, and keeps
    /// them for the analyzer's lifetime: the function table, with the names
    /// its symbol table does not give — from the export trie, the Objective-C
    /// method lists and the Swift metadata — the names of the image's
    /// classes, and the symbols of its Swift types.
    ///
    /// For a host keeping a ``CodeReferenceIndex`` of the image, so that the
    /// first query about it is answered as fast as the next: AppKit's take
    /// 0.3 s in a debug build, and hold about 14 MiB with the function table
    /// (``approximateByteCount(ofImageDataAt:)``).
    public func prepareNames(inImageAt imageIndex: Int) {
        functionTable(ofImageAt: imageIndex).fallbackNames.readEverySource()
        objectiveCClassIndex(ofImageAt: imageIndex).readEveryName()
        swiftTypeIndex(ofImageAt: imageIndex).readDescriptorSymbols()
    }

    /// The memory of what the analyzer keeps for the image now — its function
    /// table with the names read for it, its class and Swift type indexes —
    /// estimated from the collections' capacities: for a host counting a
    /// prepared image against a budget along with its ``CodeReferenceIndex``.
    public func approximateByteCount(ofImageDataAt imageIndex: Int) -> Int {
        lock.lock()
        let kept = (functionTables[imageIndex], classIndexes[imageIndex], swiftTypeIndexes[imageIndex])
        lock.unlock()
        return (kept.0?.approximateByteCount ?? 0) + (kept.1?.approximateByteCount ?? 0) + (kept.2?.approximateByteCount ?? 0)
    }

    /// Reads now what filtering the images that can reference a function or
    /// a type reads across every image the first time, and keeps it for the
    /// analyzer's lifetime: which images link which — every image's load
    /// commands — and the symbols images re-export under other names — every
    /// image's export trie, 3.9 s in a debug build.
    ///
    /// On the calling thread alone, for work in the background: reading the
    /// export tries on every core, as a query that needs them first does, is
    /// barely faster in a debug build (3.4 s on 28). A query that needs them
    /// meanwhile waits for this to finish instead of reading them again.
    public func preparePrefilters() {
        _ = linkage()
        _ = renamedReexports(concurrently: false)
    }

    /// Drops what the analyzer keeps for every image but `keptImageIndices`:
    /// function tables with the names read for them, class and Swift type
    /// indexes. A later query reads them again. What the analyzer keeps
    /// across all images — the linkage and the renamed re-exports — stays.
    ///
    /// What replacing the analyzer releases, for a host that keeps a few
    /// images prepared (``prepareNames(inImageAt:)``) and would otherwise
    /// read them all again.
    public func releaseImageData(exceptForImagesAt keptImageIndices: Set<Int>) {
        lock.lock()
        let released = (functionTables, classIndexes, swiftTypeIndexes)
        functionTables = functionTables.filter { keptImageIndices.contains($0.key) }
        classIndexes = classIndexes.filter { keptImageIndices.contains($0.key) }
        swiftTypeIndexes = swiftTypeIndexes.filter { keptImageIndices.contains($0.key) }
        lock.unlock()
        // What goes is freed here, outside the lock.
        withExtendedLifetime(released) {}
    }

    /// The references the image's functions make to any of `keys`, in table
    /// order — what a query for callers needs, without the image's whole
    /// table.
    ///
    /// A whole table of a large image runs to a hundred megabytes, and a
    /// cross-image query scans thousands of images at once; building them all
    /// is what sets the scan's peak memory.
    public func references(to keys: Set<CodeReferenceTable.Key>, inImageAt imageIndex: Int) -> [CodeReference] {
        let table = existingFunctionTable(ofImageAt: imageIndex) ?? ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex])
        var scanner = ReferenceScanner(analyzer: self, table: table, keeping: keys)
        var references: [CodeReference] = []
        for index in table.starts.indices {
            scanner.scanFunction(at: index, into: &references)
        }
        return references
    }

    // MARK: - Internals

    func existingFunctionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable? {
        lock.lock()
        defer { lock.unlock() }
        return functionTables[imageIndex]
    }

    /// The class and Swift type indexes the analyzer keeps for the image now,
    /// without building either; for tests.
    func existingIndexes(ofImageAt imageIndex: Int) -> (classIndex: ObjectiveCClassIndex?, swiftTypeIndex: SwiftTypeIndex?) {
        lock.lock()
        defer { lock.unlock() }
        return (classIndexes[imageIndex], swiftTypeIndexes[imageIndex])
    }

    /// Whether the linkage and the renamed re-exports are read; for tests.
    var hasPreparedPrefilters: Bool {
        lock.lock()
        defer { lock.unlock() }
        return linkageStorage != nil && renamedReexportStorage != nil
    }

    /// The image's function table, built on first use and then kept for the
    /// analyzer's lifetime — what naming functions needs.
    func functionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable {
        lock.lock()
        if let table = functionTables[imageIndex] {
            lock.unlock()
            return table
        }
        lock.unlock()
        // Built outside the lock: two threads may build the same table once
        // each, and the first one stored wins.
        let table = ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex])
        lock.lock()
        defer { lock.unlock() }
        if let stored = functionTables[imageIndex] { return stored }
        functionTables[imageIndex] = table
        return table
    }

    func imageIndex(containingRuntimeAddress address: UInt) -> Int? {
        var lower = 0
        var upper = textRanges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if textRanges[middle].start <= address { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let candidate = textRanges[lower - 1]
        return address < candidate.end ? candidate.imageIndex : nil
    }

    /// The image whose segments other than `__TEXT` hold the runtime
    /// `address`.
    func imageIndex(containingDataAddress address: UInt) -> Int? {
        var lower = 0
        var upper = dataRanges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if dataRanges[middle].start <= address { lower = middle + 1 } else { upper = middle }
        }
        guard lower > 0 else { return nil }
        let candidate = dataRanges[lower - 1]
        return address < candidate.end ? candidate.imageIndex : nil
    }

    /// The class object at the runtime `address`, when an image lists one
    /// there; a metaclass is reported as its class.
    func objectiveCClass(atRuntimeAddress address: UInt) -> ObjectiveCClassObject? {
        guard let imageIndex = imageIndex(containingDataAddress: address) else { return nil }
        return objectiveCClassIndex(ofImageAt: imageIndex).classObject(atRuntimeAddress: address)
    }

    /// The image's class index, built on first use and then kept for the
    /// analyzer's lifetime: a scan meets the same few hundred classes again
    /// and again.
    func objectiveCClassIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex {
        lock.lock()
        if let index = classIndexes[imageIndex] {
            lock.unlock()
            return index
        }
        lock.unlock()
        let index = ObjectiveCClassIndex(image: images[imageIndex], imageIndex: imageIndex)
        lock.lock()
        defer { lock.unlock() }
        if let stored = classIndexes[imageIndex] { return stored }
        classIndexes[imageIndex] = index
        return index
    }

    /// Built on first use and kept: reading every image's load commands takes
    /// a few tens of milliseconds.
    func linkage() -> Linkage {
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
            switch image.header.fileType {
            case .execute?: executables.append(imageIndex)
            case .bundle?: bundles.append(imageIndex)
            default: break
            }
            for (command, isReexport) in dylibCommands(ofImageAt: imageIndex) {
                for dependency in imageIndices(linkedAs: command.dylib(cmdsStart: image.cmdsStartPtr).name) where dependency != imageIndex {
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

    /// The image's dylib load commands, in order — the order a bind's or a
    /// re-export's library ordinal counts, from 1 — and whether each
    /// re-exports the dylib.
    private func dylibCommands(ofImageAt imageIndex: Int) -> [(command: DylibCommand, isReexport: Bool)] {
        images[imageIndex].loadCommands.compactMap { command in
            switch command {
            case .loadDylib(let command), .loadWeakDylib(let command), .loadUpwardDylib(let command), .lazyLoadDylib(let command):
                return (command, false)
            case .reexportDylib(let command):
                return (command, true)
            default:
                return nil
            }
        }
    }

    /// The images a load command's dylib name stands for: every image with
    /// that install name, or the image loaded from that path.
    private func imageIndices(linkedAs name: String) -> [Int] {
        indicesByInstallName[name] ?? indicesByPath[name].map { [$0] } ?? []
    }

    /// The images the image at `imageIndex` links, by library ordinal: the
    /// first element for ordinal 1. An element is empty when no image the
    /// analyzer knows is that dylib.
    func dependencyImageIndices(ofImageAt imageIndex: Int) -> [[Int]] {
        dylibCommands(ofImageAt: imageIndex).map { imageIndices(linkedAs: $0.command.dylib(cmdsStart: images[imageIndex].cmdsStartPtr).name) }
    }

    /// Built on first use and kept: every image's export trie is walked once,
    /// and what is kept is small. Built once: a caller that asks while it is
    /// being built waits for it.
    func renamedReexports(concurrently: Bool = true) -> RenamedReexportIndex {
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
        let index = RenamedReexportIndex(analyzer: self, concurrently: concurrently)
        lock.lock()
        renamedReexportStorage = index
        renamedReexportBuildCountStorage += 1
        lock.unlock()
        return index
    }

    /// How many times the renamed re-exports were built; for tests.
    var renamedReexportBuildCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return renamedReexportBuildCountStorage
    }

    /// The image's Swift type index, built on first use and then kept for the
    /// analyzer's lifetime, like the class index.
    func swiftTypeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        lock.lock()
        if let index = swiftTypeIndexes[imageIndex] {
            lock.unlock()
            return index
        }
        lock.unlock()
        let index = SwiftTypeIndex(image: images[imageIndex], imageIndex: imageIndex)
        lock.lock()
        defer { lock.unlock() }
        if let stored = swiftTypeIndexes[imageIndex] { return stored }
        swiftTypeIndexes[imageIndex] = index
        return index
    }

    /// Whether `length` bytes at the runtime `address` are mapped executable.
    func isExecutable(runtimeAddress address: UInt, length: UInt) -> Bool {
        let (end, overflow) = address.addingReportingOverflow(length)
        guard !overflow else { return false }
        return executableRanges.contains { $0.lowerBound <= address && end <= $0.upperBound }
    }

    /// Whether `length` bytes at the runtime `address` are mapped at all.
    func isMapped(runtimeAddress address: UInt, length: UInt) -> Bool {
        let (end, overflow) = address.addingReportingOverflow(length)
        guard !overflow else { return false }
        return mappedRanges.contains { $0.lowerBound <= address && end <= $0.upperBound }
    }

    /// How many bytes from the runtime `address` on may be read: up to the
    /// end of the mapping that holds it, or none.
    func mappedLength(fromRuntimeAddress address: UInt) -> UInt {
        guard let range = mappedRanges.first(where: { $0.contains(address) }) else { return 0 }
        return range.upperBound - address
    }
}
