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
    /// Each image's path, by position in ``images``.
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

    private let indicesByPath: [String: Int]
    private let lock = NSLock()
    private var functionTables: [Int: ImageFunctionTable] = [:]
    private var classIndexes: [Int: ObjectiveCClassIndex] = [:]

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
        for imageIndex in 0 ..< _dyld_image_count() {
            guard let header = _dyld_get_image_header(imageIndex) else { continue }
            let image = MachOImage(ptr: header)
            guard !image.header.isInDyldCache else { continue }
            images.append(image)
        }

        var imagePaths: [String] = []
        var indicesByPath: [String: Int] = [:]
        var textRanges: [ImageAddressRange] = []
        var dataRanges: [ImageAddressRange] = []
        for (imageIndex, image) in images.enumerated() {
            let path = image.path ?? ""
            imagePaths.append(path)
            if indicesByPath[path] == nil { indicesByPath[path] = imageIndex }
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
        self.textRanges = textRanges
        self.dataRanges = dataRanges
        self.executableRanges = executableRanges
        self.mappedRanges = mappedRanges

        // The runtime's entry points, found by name in the runtime libraries.
        var messageSendLocations = Set<CodeLocation>()
        var superMessageSendLocations = Set<CodeLocation>()
        var runtimeHelperLocations = Set<CodeLocation>()
        var classReturningFunctionLocations = Set<CodeLocation>()
        for (imageIndex, path) in imagePaths.enumerated() where Self.isRuntimeLibrary(path) {
            func classify(_ name: UnsafePointer<CChar>, at location: CodeLocation) {
                if strcmp(name, "_objc_msgSend") == 0 {
                    messageSendLocations.insert(location)
                } else if strcmp(name, "_objc_msgSendSuper2") == 0 {
                    superMessageSendLocations.insert(location)
                } else if strcmp(name, "_objc_opt_self") == 0 || strcmp(name, "_objc_opt_class") == 0 || strcmp(name, "_swift_getInitializedObjCClass") == 0 {
                    classReturningFunctionLocations.insert(location)
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

    /// The position in ``images`` of the image at `path` — its install name
    /// for a shared cache image.
    public func imageIndex(forPath path: String) -> Int? {
        indicesByPath[path]
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
