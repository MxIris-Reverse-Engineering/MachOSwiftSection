import Foundation
import MachOKit

/// Reads what each function of an image references, from its arm64
/// machine code, inside the current process.
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
/// The facade over three layers: the language-free core
/// (`CrossReferenceCore`: images, function tables, the instruction scan),
/// the Objective-C layer (`CrossReferenceObjC`) and the Swift layer, this
/// module. The two language layers plug into the core's scan as recognizers;
/// the analyzer builds a session of each for every scan and turns what they
/// record into ``CodeReference``s.
///
/// Only arm64 and arm64e are read. Evolution proposals
/// `cross-reference-analysis`, `offline-cross-references-and-symbolication`.
public final class CrossReferenceAnalyzer: @unchecked Sendable {
    let imageSet: CodeImageSet
    let objectiveC: ObjCCodeReferenceRecognizer
    let swift: SwiftCodeReferenceRecognizer

    /// Every image the analyzer knows, shared cache first — for the
    /// in-process analyzer. Empty for one made from files, whose images are
    /// no `MachOImage`s: ``imagePaths`` and ``imageCount`` list every image
    /// in either kind.
    public let images: [MachOImage]

    /// How many images the analyzer covers, in either kind.
    public var imageCount: Int { imageSet.images.count }

    /// Whether a whole-image scan records the string literals code takes
    /// the address of (``CodeReferenceTarget/cString(_:)``,
    /// ``CodeReferenceTarget/constantString(_:)``). Off unless asked for when
    /// the analyzer is made: they are many, and a host keeping indexes for
    /// every image needs none. A query for a string key looks for strings
    /// either way.
    public let recordsStringReferences: Bool
    /// Each image's path, by position in ``images``: where dyld loaded it —
    /// for a shared cache image, its install name.
    ///
    /// Not the install name for an image outside the cache: an app's main
    /// executable and its bundles have none, and its frameworks have an
    /// `@rpath/…` one, which names no file.
    public var imagePaths: [String] { imageSet.imagePaths }

    /// What the two language layers say about runtime libraries and helpers.
    static let runtimeLibraryRules = RuntimeLibraryRules(
        isRuntimeLibrary: { ObjCRuntimeFunctions.isRuntimeLibrary($0) || SwiftRuntimeFunctions.isRuntimeLibrary($0) },
        isRuntimeHelperName: { ObjCRuntimeHelperNames.isRuntimeHelper($0) || SwiftRuntimeHelperNames.isRuntimeHelper($0) }
    )

    /// The analyzer for the current process, or `nil` when it does not run
    /// arm64 code.
    public convenience init?() {
        guard let parts = Self.makeParts(CodeImageSet.inProcess) else { return nil }
        self.init(parts: parts)
    }

    /// Analyzes every image of a dyld shared cache read from disk, such as an
    /// archived one or another device's: the images' code, their slots and
    /// their metadata are read from the cache's files, where MachOKit mapped
    /// them, and addresses in and out are the cache's own, unslid ones.
    ///
    /// - Throws: ``FileAnalysisError`` when the cache is not an arm64 one.
    public convenience init(dyldCache: FullDyldCache, recordingStringReferences: Bool = false) throws {
        guard dyldCache.cpu.type == .arm64 else { throw FileAnalysisError(code: .unsupportedArchitecture, path: dyldCache.url.path) }
        self.init(parts: Self.makeParts { CodeImageSet.dyldCache(dyldCache, rules: $0, visitingRuntimeLibrarySymbols: $1) }!, recordsStringReferences: recordingStringReferences)
    }

    /// Analyzes standalone Mach-O files, such as an app's executable and its
    /// embedded frameworks. A file's addresses in and out are its own; the
    /// analyzer keeps the files apart internally, as dyld would. A call into
    /// a library none of the files is stays an imported symbol, named by the
    /// file's bind; a bind to a symbol one of the files exports — its own,
    /// for a self-bind — leads to it.
    ///
    /// - Throws: ``FileAnalysisError`` when a file is not an arm64 slice.
    public convenience init(machOFiles: [MachOFile], recordingStringReferences: Bool = false) throws {
        if let file = machOFiles.first(where: { $0.header.cpuType != .arm64 }) {
            throw FileAnalysisError(code: .unsupportedArchitecture, path: file.url.path)
        }
        self.init(parts: Self.makeParts { CodeImageSet.files(machOFiles, rules: $0, visitingRuntimeLibrarySymbols: $1) }!, recordsStringReferences: recordingStringReferences)
    }

    /// What a set of images is analyzed with: the set, and the runtime's
    /// entry points the language layers found by name in its runtime
    /// libraries, in the one pass the set makes over their symbols.
    private typealias Parts = (imageSet: CodeImageSet, objectiveCFunctions: ObjCRuntimeFunctions, swiftFunctions: SwiftRuntimeFunctions)

    private static func makeParts(
        _ makeImageSet: (RuntimeLibraryRules, (UnsafePointer<CChar>, CodeLocation) -> Void) -> CodeImageSet?
    ) -> Parts? {
        var objectiveCFunctions = ObjCRuntimeFunctions()
        var swiftFunctions = SwiftRuntimeFunctions()
        let imageSet = makeImageSet(runtimeLibraryRules) { name, location in
            objectiveCFunctions.consider(name, at: location)
            swiftFunctions.consider(name, at: location)
        }
        guard let imageSet else { return nil }
        return (imageSet, objectiveCFunctions, swiftFunctions)
    }

    private init(parts: Parts, recordsStringReferences: Bool = false) {
        self.recordsStringReferences = recordsStringReferences
        self.imageSet = parts.imageSet
        self.images = parts.imageSet.images.compactMap { $0.reader.asMachOImage }
        self.objectiveC = ObjCCodeReferenceRecognizer(images: parts.imageSet, runtimeFunctions: parts.objectiveCFunctions)
        self.swift = SwiftCodeReferenceRecognizer(images: parts.imageSet, runtimeFunctions: parts.swiftFunctions)
    }

    // MARK: - Images and functions

    /// The position in ``images`` of the image at `path`: where dyld loaded
    /// it, which for a shared cache image is its install name. An install
    /// name finds an image outside the cache too.
    public func imageIndex(forPath path: String) -> Int? {
        imageSet.imageIndex(forPath: path)
    }

    /// The image whose `__TEXT` segment holds the runtime address `address`,
    /// and the unslid address there.
    public func location(ofRuntimeAddress address: UInt) -> CodeLocation? {
        imageSet.location(ofRuntimeAddress: address)
    }

    /// Every function of the image, sorted by address.
    public func functions(inImageAt imageIndex: Int) -> [CodeFunction] {
        let table = functionTable(ofImageAt: imageIndex)
        return table.starts.indices.map { codeFunction(at: $0, in: table) }
    }

    /// The function whose code holds `location`.
    public func function(containing location: CodeLocation) -> CodeFunction? {
        let table = functionTable(ofImageAt: location.imageIndex)
        guard let index = table.functionIndex(containing: location.address) else { return nil }
        return codeFunction(at: index, in: table)
    }

    /// The functions holding each of `locations`, keyed by the location
    /// asked about — for naming the results of a query that touched many
    /// images. Each image's table is built for the lookup and dropped,
    /// unless the analyzer already holds it; a location in no function is
    /// left out.
    public func functions(containing locations: some Sequence<CodeLocation>) -> [CodeLocation: CodeFunction] {
        var functions: [CodeLocation: CodeFunction] = [:]
        for (imageIndex, imageLocations) in Dictionary(grouping: locations, by: \.imageIndex) {
            let table = imageSet.transientFunctionTable(ofImageAt: imageIndex)
            for location in imageLocations {
                guard let index = table.functionIndex(containing: location.address) else { continue }
                functions[location] = codeFunction(at: index, in: table)
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

    /// The function at `index` of `table`, named by its symbol, or — when
    /// the symbol table names none — by the export trie, the Objective-C
    /// method lists and the Swift metadata, tried in that order, each read
    /// only when a function is still unnamed after the ones before it.
    func codeFunction(at index: Int, in table: ImageFunctionTable) -> CodeFunction {
        let start = table.starts[index]
        var name: CodeFunction.Name? = table.primaryName(ofFunctionAt: index).map { .symbol(String(cString: $0)) }
        var foldedSymbolNames = table.foldedNames[start]?.map { String(cString: $0) } ?? []
        if name == nil {
            if let names = ExportedFunctionNames.of(table).namesByAddress[start], let first = names.first {
                name = .symbol(first)
                foldedSymbolNames = Array(names.dropFirst())
            } else if let method = ObjCMethodNames.of(table).methodsByAddress[start] {
                name = .objectiveCMethod(className: method.className, selector: method.selector, isClassMethod: method.isClassMethod)
                foldedSymbolNames = []
            } else if let mangledName = SwiftMetadataNames.of(table).name(at: start) {
                name = .swiftMetadata(mangledName: mangledName)
                foldedSymbolNames = []
            }
        }
        return CodeFunction(
            location: CodeLocation(imageIndex: table.imageIndex, address: start),
            size: Int(table.end(ofFunctionAt: index) - start),
            name: name,
            foldedSymbolNames: foldedSymbolNames,
            isRuntimeHelper: table.runtimeHelperStarts.contains(start)
        )
    }

    // MARK: - References

    /// What `function` references, in instruction order.
    public func references(madeBy function: CodeFunction) -> [CodeReference] {
        let table = functionTable(ofImageAt: function.location.imageIndex)
        guard let index = table.functionIndex(containing: function.location.address) else { return [] }
        return scan(table) { scanner, _ in scanner.scanFunction(at: index) }
    }

    /// What every function of the image references, grouped by what it
    /// references.
    ///
    /// The image's function table is built for the scan and dropped after
    /// it, unless the analyzer already holds it: a cross-image query scans
    /// thousands of images, and keeping every table it touched held 1.5 GB
    /// after a scan of a macOS 27.2 cache.
    public func referenceTable(ofImageAt imageIndex: Int) -> CodeReferenceTable {
        let table = imageSet.transientFunctionTable(ofImageAt: imageIndex)
        let references = scan(table) { scanner, _ in
            for index in table.starts.indices {
                scanner.scanFunction(at: index)
            }
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
        var builder = CodeReferenceIndex.Builder(imageIndex: imageIndex, codeStart: table.textStart)
        let functionCount = table.starts.count
        var isStopped = false
        _ = scan(table) { scanner, collector in
            for index in table.starts.indices {
                if let reportProgress, index % Self.referenceIndexProgressStride == 0, !reportProgress(index, functionCount) {
                    isStopped = true
                    return
                }
                collector.references.removeAll(keepingCapacity: true)
                scanner.scanFunction(at: index)
                for reference in collector.references {
                    builder.add(reference)
                }
            }
        }
        if isStopped { return nil }
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
        let table = functionTable(ofImageAt: imageIndex)
        _ = ExportedFunctionNames.of(table)
        objectiveC.readMethodNames(of: table)
        SwiftMetadataNames.of(table).readEverySource()
        objectiveC.classIndex(ofImageAt: imageIndex).readEveryName()
        swift.typeIndex(ofImageAt: imageIndex).readDescriptorSymbols()
    }

    /// The memory of what the analyzer keeps for the image now — its function
    /// table with the names read for it, its class and Swift type indexes —
    /// estimated from the collections' capacities: for a host counting a
    /// prepared image against a budget along with its ``CodeReferenceIndex``.
    public func approximateByteCount(ofImageDataAt imageIndex: Int) -> Int {
        let table = imageSet.existingFunctionTable(ofImageAt: imageIndex)
        let classIndex = objectiveC.existingClassIndex(ofImageAt: imageIndex)
        let typeIndex = swift.existingTypeIndex(ofImageAt: imageIndex)
        return (table?.approximateByteCount ?? 0) + (classIndex?.approximateByteCount ?? 0) + (typeIndex?.approximateByteCount ?? 0)
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
        _ = imageSet.linkage()
        _ = imageSet.renamedReexports(concurrently: false)
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
        let released = (
            imageSet.releaseFunctionTables(exceptForImagesAt: keptImageIndices),
            objectiveC.releaseClassIndexes(exceptForImagesAt: keptImageIndices),
            swift.releaseTypeIndexes(exceptForImagesAt: keptImageIndices)
        )
        // What goes is freed here, outside every lock.
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
        let table = imageSet.transientFunctionTable(ofImageAt: imageIndex)
        return scan(table, keeping: keys) { scanner, _ in
            for index in table.starts.indices {
                scanner.scanFunction(at: index)
            }
        }
    }

    // MARK: - Scanning

    /// Scans with a session of each language layer, the Objective-C one
    /// first: `body` drives the scanner, and what the sessions and the core
    /// record — `keys` and `query` filtering it, as
    /// ``references(to:inImageAt:)`` and the type queries do — is returned.
    func scan(
        _ table: ImageFunctionTable,
        keeping keys: Set<CodeReferenceTable.Key>? = nil,
        matching query: SwiftTypeQuery? = nil,
        followsBranches: Bool = true,
        _ body: (inout ReferenceScanner, ReferenceCollector) -> Void
    ) -> [CodeReference] {
        let collector = ReferenceCollector(keeping: keys, matching: query)
        let sessions: [any CodeReferenceRecognitionSession] = [
            objectiveC.makeSession(table: table, recording: collector, findsClassReferences: collector.findsTypeReferences),
            swift.makeSession(table: table, recording: collector, findsTypeReferences: collector.findsTypeReferences),
        ]
        var scanner = ReferenceScanner(
            images: imageSet,
            table: table,
            sessions: sessions,
            recording: collector,
            followsBranches: followsBranches,
            recordsStringReferences: collector.findsStrings(whenWholeImage: recordsStringReferences),
            recordsImportedSymbolReferences: collector.findsImportedSymbolReferences
        )
        body(&scanner, collector)
        return collector.references
    }

    // MARK: - Internals

    /// Where every read of image memory goes.
    var memory: any CrossReferenceMemory { imageSet.memory }

    /// Where `objc_msgSend` lives, the original and the copies the cache
    /// carries for its shared selector stubs.
    var messageSendLocations: Set<CodeLocation> { objectiveC.runtimeFunctions.messageSendLocations }

    func existingFunctionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable? {
        imageSet.existingFunctionTable(ofImageAt: imageIndex)
    }

    /// The class and Swift type indexes the analyzer keeps for the image now,
    /// without building either; for tests.
    func existingIndexes(ofImageAt imageIndex: Int) -> (classIndex: ObjectiveCClassIndex?, swiftTypeIndex: SwiftTypeIndex?) {
        (objectiveC.existingClassIndex(ofImageAt: imageIndex), swift.existingTypeIndex(ofImageAt: imageIndex))
    }

    /// Whether every name source of the image's kept table has been read;
    /// for tests.
    func hasReadEveryNameSource(ofImageAt imageIndex: Int) -> Bool {
        guard let table = existingFunctionTable(ofImageAt: imageIndex) else { return false }
        return table.existingAttachment(ExportedFunctionNames.self) != nil
            && ObjCMethodNames.existing(in: table) != nil
            && SwiftMetadataNames.existing(in: table)?.hasReadEverySource == true
    }

    /// Whether the linkage and the renamed re-exports are read; for tests.
    var hasPreparedPrefilters: Bool { imageSet.hasPreparedPrefilters }

    /// How many times the renamed re-exports were built; for tests.
    var renamedReexportBuildCount: Int { imageSet.renamedReexportBuildCount }

    /// The image's function table, built on first use and then kept for the
    /// analyzer's lifetime — what naming functions needs.
    func functionTable(ofImageAt imageIndex: Int) -> ImageFunctionTable {
        imageSet.functionTable(ofImageAt: imageIndex)
    }

    func imageIndex(containingRuntimeAddress address: UInt) -> Int? {
        imageSet.imageIndex(containingRuntimeAddress: address)
    }

    func imageIndex(containingDataAddress address: UInt) -> Int? {
        imageSet.imageIndex(containingDataAddress: address)
    }

    func objectiveCClassIndex(ofImageAt imageIndex: Int) -> ObjectiveCClassIndex {
        objectiveC.classIndex(ofImageAt: imageIndex)
    }

    func swiftTypeIndex(ofImageAt imageIndex: Int) -> SwiftTypeIndex {
        swift.typeIndex(ofImageAt: imageIndex)
    }

    func renamedReexports(concurrently: Bool = true) -> RenamedReexportIndex {
        imageSet.renamedReexports(concurrently: concurrently)
    }

    /// Whether `length` bytes at the runtime `address` are mapped at all.
    func isMapped(runtimeAddress address: UInt, length: UInt) -> Bool {
        imageSet.isMapped(runtimeAddress: address, length: length)
    }
}

/// Turns what one scan's sessions and core record into ``CodeReference``s,
/// keeping only what the query asked for.
///
/// Used from the one thread of its scan.
final class ReferenceCollector: ObjCCodeReferenceRecording, SwiftCodeReferenceRecording {
    @exclusivity(unchecked)
    var references: [CodeReference] = []
    /// When set, only references filed under one of these keys are kept.
    private let keptKeys: Set<CodeReferenceTable.Key>?
    /// When set, the references to one Swift type are kept besides the
    /// ones `keptKeys` names.
    private let swiftTypeQuery: SwiftTypeQuery?
    /// Whether the scan looks for class and type references at all. A query
    /// for the callers of a selector or a function keeps none, and skipping
    /// them keeps it as fast as before they existed; a send's class-literal
    /// receiver is still told, at the send.
    let findsTypeReferences: Bool
    @exclusivity(unchecked)
    private var importedNames: [UInt: String] = [:]

    init(keeping keptKeys: Set<CodeReferenceTable.Key>?, matching swiftTypeQuery: SwiftTypeQuery?) {
        self.keptKeys = keptKeys ?? (swiftTypeQuery == nil ? nil : [])
        self.swiftTypeQuery = swiftTypeQuery
        self.findsTypeReferences = swiftTypeQuery != nil || keptKeys.map { keys in
            keys.contains { key in
                switch key {
                case .objectiveCClass, .swiftTypeDescriptor, .instanceVariable: return true
                case .function, .selector, .importedSymbol, .cString, .constantString: return false
                }
            }
        } ?? true
        self.findsImportedSymbolReferences = keptKeys.map { keys in
            keys.contains { if case .importedSymbol = $0 { true } else { false } }
        } ?? true
    }

    /// Whether loads from slots that bind to another image's symbol are
    /// recorded: for a whole image, or for a query for an imported name.
    let findsImportedSymbolReferences: Bool

    /// Whether the scan looks for string literals: for a whole image as the
    /// analyzer was made to, and for any query for a string key.
    func findsStrings(whenWholeImage wholeImageRecordsStrings: Bool) -> Bool {
        guard let keptKeys, swiftTypeQuery == nil else { return keptKeys == nil && wholeImageRecordsStrings }
        return keptKeys.contains { key in
            switch key {
            case .cString, .constantString: true
            default: false
            }
        }
    }

    private func keep(_ target: CodeReferenceTarget, at site: ScanSite, isRuntimeHelperCall: Bool = false) {
        if let keptKeys {
            let isFiled = target.tableKey.map(keptKeys.contains) ?? false
            guard isFiled || swiftTypeQuery?.matches(target) == true else { return }
        }
        references.append(CodeReference(function: site.function, instructionAddress: site.instructionAddress, kind: site.kind, target: target, route: site.route, isRuntimeHelperCall: isRuntimeHelperCall))
    }

    func recordCall(to target: ResolvedCallTarget, targetAddress: UInt64, at site: ScanSite, isRuntimeHelperCall: Bool) {
        switch target {
        case .function(let location):
            keep(.function(location), at: site, isRuntimeHelperCall: isRuntimeHelperCall)
        case .importedSymbol(let name):
            keep(.importedSymbol(name: importedSymbolName(name)), at: site, isRuntimeHelperCall: isRuntimeHelperCall)
        case .registerSettingTrampoline, .unrecognized:
            keep(.unrecognized(address: targetAddress), at: site)
        }
    }

    func recordIndirectCall(_ evidence: IndirectCallEvidence, at site: ScanSite) {
        keep(.indirect(evidence), at: site)
    }

    func recordMessageSend(selector: String, receiver: ReceiverClassHint, at site: ScanSite) {
        keep(.messageSend(selector: selector, receiver: receiver), at: site)
    }

    func recordSuperMessageSend(selector: String, className: String?, at site: ScanSite) {
        keep(.superMessageSend(selector: selector, className: className), at: site)
    }

    func recordClassReference(_ classObject: ObjectiveCClassObject, at site: ScanSite) {
        keep(.objectiveCClass(name: classObject.name, location: classObject.location), at: site)
    }

    func recordInstanceVariableReference(className: String, name: String, at site: ScanSite) {
        keep(.objectiveCInstanceVariable(className: className, name: name), at: site)
    }

    func recordString(_ string: StringLiteralReference, at site: ScanSite) {
        switch string {
        case .cString(let characters):
            keep(.cString(characters), at: site)
        case .constantString(let characters):
            keep(.constantString(characters), at: site)
        }
    }

    func recordImportedSymbolReference(named name: String, at site: ScanSite) {
        keep(.importedSymbol(name: name), at: site)
    }

    func recordSwiftType(descriptor: CodeLocation, at site: ScanSite) {
        keep(.swiftType(descriptor: descriptor), at: site)
    }

    func recordSwiftTypeName(_ name: SwiftTypeName, at site: ScanSite) {
        keep(.swiftTypeName(name), at: site)
    }

    private func importedSymbolName(_ pointer: UnsafePointer<CChar>) -> String {
        let key = UInt(bitPattern: pointer)
        if let known = importedNames[key] { return known }
        let name = String(cString: pointer)
        importedNames[key] = name
        return name
    }
}
