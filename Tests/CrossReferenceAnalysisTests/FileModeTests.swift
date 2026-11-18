import Foundation
import Testing
import MachOKit
import MachOKitExtensions
import ARM64InstructionDecoding
@testable import CrossReferenceAnalysis

/// The analyzer made from the running system's dyld shared cache file:
/// the same images the process maps, read where they lie on disk.
enum RunningCacheFileAnalyzer {
    static let analyzer: CrossReferenceAnalyzer? = FullDyldCache.cachedHost.flatMap { try? CrossReferenceAnalyzer(dyldCache: $0) }
}

/// The analyzer made from files reads what the in-process analyzer reads,
/// and reaches what the process cannot: archived caches, another device's
/// cache, an app on disk (evolution proposal
/// `offline-cross-references-and-symbolication`, step 4).
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil && RunningCacheFileAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct FileModeTests {
    /// Every reference of a large image, read from the cache file, is the
    /// one the process reads from memory: the same functions, the same
    /// sites, the same targets — a class object a GOT slot rebases to, a
    /// selector a stub sets, a Swift type an accessor names.
    @Test(arguments: ReferenceTableDigestTests.imageSuffixes)
    func fileModeMatchesInProcessReferencesOnTheRunningSystemCache(imageSuffix: String) throws {
        let inProcess = try #require(SharedAnalyzer.analyzer)
        let fromFile = try #require(RunningCacheFileAnalyzer.analyzer)
        let inProcessIndex = try #require(inProcess.imagePaths.firstIndex { $0.hasSuffix(imageSuffix) })
        let fileIndex = try #require(fromFile.imagePaths.firstIndex { $0.hasSuffix(imageSuffix) })
        let inProcessLines = inProcess.referenceTable(ofImageAt: inProcessIndex).references.map { Self.spelling(of: $0, imagePaths: inProcess.imagePaths) }
        let fileLines = fromFile.referenceTable(ofImageAt: fileIndex).references.map { Self.spelling(of: $0, imagePaths: fromFile.imagePaths) }
        #expect(fileLines.count == inProcessLines.count, "\(imageSuffix): \(fileLines.count) references from the file, \(inProcessLines.count) in the process")
        let differences = zip(inProcessLines, fileLines).filter { $0 != $1 }.prefix(5)
        #expect(differences.isEmpty, "\(imageSuffix), first differences (process, file):\n\(differences.map { "\($0)\n\($1)" }.joined(separator: "\n\n"))")
        #expect(inProcessLines.count > 100_000)
    }

    /// Every function of an image is named from the file as the process
    /// names it: from its symbols and export trie, and — where those leave
    /// it unnamed — from the Objective-C method lists and the Swift
    /// metadata, which read through each reader's own API.
    @Test(arguments: ReferenceTableDigestTests.imageSuffixes + ["/Matter.framework/Versions/A/Matter"])
    func fileModeNamesFunctionsAsTheProcessDoes(imageSuffix: String) throws {
        let inProcess = try #require(SharedAnalyzer.analyzer)
        let fromFile = try #require(RunningCacheFileAnalyzer.analyzer)
        let inProcessIndex = try #require(inProcess.imagePaths.firstIndex { $0.hasSuffix(imageSuffix) })
        let fileIndex = try #require(fromFile.imagePaths.firstIndex { $0.hasSuffix(imageSuffix) })
        func spelling(of function: CodeFunction) -> String {
            "\(function.location.address) \(function.size) \(Self.describe(function.name)) \(function.foldedSymbolNames) \(function.isRuntimeHelper)"
        }
        let inProcessFunctions = inProcess.functions(inImageAt: inProcessIndex)
        let inProcessLines = inProcessFunctions.map(spelling(of:))
        let fileLines = fromFile.functions(inImageAt: fileIndex).map(spelling(of:))
        #expect(fileLines.count == inProcessLines.count)
        let differences = zip(inProcessLines, fileLines).filter { $0 != $1 }.prefix(5)
        #expect(differences.isEmpty, "\(imageSuffix), first differences (process, file):\n\(differences.map { "\($0)\n\($1)" }.joined(separator: "\n\n"))")
        #expect(inProcessFunctions.count > 1000)
    }

    /// The two fallback sources read every name from the file that they
    /// read from memory: the Objective-C method lists of AppKit (whose
    /// classes the runtime has realized in the process) and of Matter, and
    /// the Swift metadata of SwiftUICore — each through its reader's own
    /// API, in which a method's `imp` and a descriptor's offset count
    /// differently.
    @Test func fileModeReadsTheFallbackNameSourcesAsTheProcessDoes() throws {
        let inProcess = try #require(SharedAnalyzer.analyzer)
        let fromFile = try #require(RunningCacheFileAnalyzer.analyzer)
        func tables(_ suffix: String) throws -> (ImageFunctionTable, ImageFunctionTable) {
            let inProcessIndex = try #require(inProcess.imagePaths.firstIndex { $0.hasSuffix(suffix) })
            let fileIndex = try #require(fromFile.imagePaths.firstIndex { $0.hasSuffix(suffix) })
            return (inProcess.imageSet.transientFunctionTable(ofImageAt: inProcessIndex), fromFile.imageSet.transientFunctionTable(ofImageAt: fileIndex))
        }
        for suffix in ["/AppKit.framework/Versions/C/AppKit", "/Matter.framework/Versions/A/Matter"] {
            let (inProcessTable, fileTable) = try tables(suffix)
            func spelled(_ names: ObjCMethodNames) -> [UInt64: String] {
                names.methodsByAddress.mapValues { "\($0.isClassMethod ? "+" : "-")[\($0.className) \($0.selector)]" }
            }
            let inProcessMethods = spelled(ObjCMethodNames.of(inProcessTable))
            let fileMethods = spelled(ObjCMethodNames.of(fileTable))
            #expect(inProcessMethods.count > 100, "\(suffix): \(inProcessMethods.count) methods in the process")
            let differing = inProcessMethods.filter { fileMethods[$0.key] != $0.value }.prefix(5)
            #expect(fileMethods.count == inProcessMethods.count && differing.isEmpty, "\(suffix): \(fileMethods.count) methods from the file, \(inProcessMethods.count) in the process; differing: \(Array(differing))")
        }
        let (inProcessTable, fileTable) = try tables("/SwiftUICore.framework/Versions/A/SwiftUICore")
        let inProcessNames = SwiftMetadataNames.of(inProcessTable)
        let fileNames = SwiftMetadataNames.of(fileTable)
        var named = 0
        var differing: [String] = []
        for start in inProcessTable.starts {
            let inProcessName = inProcessNames.name(at: start)
            if inProcessName != nil { named += 1 }
            if fileNames.name(at: start) != inProcessName, differing.count < 5 { differing.append("\(String(start, radix: 16)): \(inProcessName ?? "nil") / \(fileNames.name(at: start) ?? "nil")") }
        }
        #expect(named > 1000, "the metadata names only \(named) functions of SwiftUICore")
        #expect(differing.isEmpty, "process / file: \(differing)")
    }

    /// The prefilters read the same slots and symbols from the file: the
    /// images that may send a selector are the process's, less the images
    /// it loaded outside the cache.
    @Test(arguments: ["makeKeyAndOrderFront:", "init"])
    func fileModePrefiltersSelectorsAsTheProcessDoes(selector: String) throws {
        let inProcess = try #require(SharedAnalyzer.analyzer)
        let fromFile = try #require(RunningCacheFileAnalyzer.analyzer)
        let cachePaths = Set(fromFile.imagePaths)
        let inProcessPaths = Set(inProcess.imageIndices(referencingSelector: selector, among: inProcess.imagePaths.indices).map { inProcess.imagePaths[$0] }).intersection(cachePaths)
        let filePaths = Set(fromFile.imageIndices(referencingSelector: selector, among: fromFile.imagePaths.indices).map { fromFile.imagePaths[$0] })
        #expect(filePaths == inProcessPaths, "only in the process: \(inProcessPaths.subtracting(filePaths).sorted().prefix(5)); only in the file: \(filePaths.subtracting(inProcessPaths).sorted().prefix(5))")
        #expect(filePaths.count > 10)
    }

    /// A reference spelled with its images by path rather than by position,
    /// which differs between the two analyzers: the process lists the images
    /// loaded outside the cache too.
    private static func spelling(of reference: CodeReference, imagePaths: [String]) -> String {
        let spelling = ReferenceTableDigestTests.spelling(of: reference)
        let range = NSRange(location: 0, length: spelling.utf16.count)
        var result = ""
        var last = spelling.startIndex
        for match in imageIndexPattern.matches(in: spelling, range: range) {
            guard let whole = Range(match.range, in: spelling), let number = Range(match.range(at: 1), in: spelling), let imageIndex = Int(spelling[number]) else { continue }
            result += spelling[last ..< whole.lowerBound]
            result += "image: \(imageIndex < imagePaths.count ? imagePaths[imageIndex] : "?")"
            last = whole.upperBound
        }
        return result + spelling[last...]
    }

    private static let imageIndexPattern = try! NSRegularExpression(pattern: #"imageIndex: (\d+)"#)

    /// The two callers of `UINSPasteboardWritingItemProvider` in macOS 27.0
    /// and 27.2 load UIKitMacHelper's own class object from a GOT slot,
    /// which no disassembler names: the slot holds a cache-relative rebase
    /// of the class's address.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e"), "needs the archived macOS caches"), arguments: ["27.0", "27.2"])
    func archivedCacheFindsBothCallersOfPasteboardWritingItemProvider(version: String) throws {
        let cachePath = "/Volumes/DyldSharedCaches/macOS/\(version)/dyld_shared_cache_arm64e"
        try #require(FileManager.default.fileExists(atPath: cachePath), "no archived macOS \(version) cache")
        let analyzer = try CrossReferenceAnalyzer(dyldCache: FullDyldCache(url: URL(fileURLWithPath: cachePath)))
        let macHelper = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/UIKitMacHelper.framework/Versions/A/UIKitMacHelper") })
        let className = "UINSPasteboardWritingItemProvider"
        #expect(analyzer.objectiveCClassLocations(named: className, inImageAt: macHelper).count == 1)
        let references = analyzer.references(to: [.objectiveCClass(className)], inImageAt: macHelper)
        let callerNames = Set(analyzer.functions(containing: references.map(\.function)).values.map { Self.describe($0.name) })
        #expect(callerNames == [
            "-[UINSInputView writeSelectionToPasteboard:types:]",
            "-[UINSSceneWindowController window:shouldDragDocumentWithEvent:from:withPasteboard:]",
        ], "macOS \(version): \(references)")
    }

    private static func describe(_ name: CodeFunction.Name?) -> String {
        switch name {
        case .symbol(let symbol)?:
            return symbol
        case .objectiveCMethod(let className, let selector, let isClassMethod)?:
            return "\(isClassMethod ? "+" : "-")[\(className) \(selector)]"
        case .swiftMetadata(let mangledName)?:
            return mangledName
        case nil:
            return "<unnamed>"
        }
    }

    /// An iOS device cache is too large for a `bl` to reach across its
    /// subcaches: a call to another image goes through stub islands between
    /// the images. A send through one is still a send.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/Volumes/DyldSharedCaches/iOS/26.3.1/dyld_shared_cache_arm64e"), "needs the archived iOS 26.3.1 device cache"))
    func archivedCacheFollowsStubIslandsForSelectorSends() throws {
        let analyzer = try CrossReferenceAnalyzer(dyldCache: FullDyldCache(url: URL(fileURLWithPath: "/Volumes/DyldSharedCaches/iOS/26.3.1/dyld_shared_cache_arm64e")))
        let swiftUI = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/SwiftUI.framework/SwiftUI") })
        let table = analyzer.referenceTable(ofImageAt: swiftUI)
        var sendsThroughIslands = 0
        for reference in table.references {
            guard case .messageSend = reference.target,
                  let word = analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: swiftUI, address: reference.instructionAddress))),
                  let branchTarget = ARM64InstructionWord.callTarget(word, at: reference.instructionAddress) ?? ARM64InstructionWord.branchTarget(word, at: reference.instructionAddress)
            else { continue }
            // The `bl` lands between the images: on an island.
            if analyzer.imageSet.imageIndex(containingRuntimeAddress: UInt(branchTarget)) == nil {
                sendsThroughIslands += 1
                #expect(reference.route == .stubIsland, "\(String(reference.instructionAddress, radix: 16)): \(reference.route)")
            }
        }
        #expect(sendsThroughIslands > 100, "only \(sendsThroughIslands) sends of SwiftUI go through stub islands")
    }

    /// A standalone library linked `-interposable` calls its own exported
    /// function the way it calls another library's: through a stub whose
    /// slot binds by name, to itself. The bind leads to the function; a call
    /// into a library the analyzer does not cover stays an imported name.
    @Test func standaloneAppResolvesImportedAndSelfBoundSymbols() throws {
        let (directory, library) = try CompiledFixture.build(
            libraryName: "libSelfBound.dylib",
            sources: ["SelfBound.c": """
            #include <stdio.h>
            __attribute__((noinline)) int selfBoundCallee(int value) { return value * 3; }
            int selfBoundCaller(int value) { puts("called"); return selfBoundCallee(value) + 1; }
            """],
            compilerArguments: ["-O1", "-Wl,-interposable"]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: library)])
        #expect(analyzer.imageCount == 1)
        #expect(analyzer.images.isEmpty)
        let functions = analyzer.functions(inImageAt: 0)
        let caller = try #require(functions.first { $0.name == .symbol("_selfBoundCaller") })
        let callee = try #require(functions.first { $0.name == .symbol("_selfBoundCallee") })
        let targets = analyzer.references(madeBy: caller).map(\.target)
        #expect(targets.contains(.function(callee.location)), "\(targets)")
        #expect(targets.contains(.importedSymbol(name: "_puts")), "\(targets)")
        #expect(!targets.contains(.importedSymbol(name: "_selfBoundCallee")))
    }

    /// A C++ function's exception cleanup — the landing pad that runs a
    /// destructor and resumes unwinding — lies after its `retab`, where no
    /// function start marks it. The scan runs past a return to the next
    /// start, so the cleanup's calls are found: `_Unwind_Resume` is called
    /// nowhere else.
    @Test func fileModeScansExceptionCleanupCodeAfterReturn() throws {
        let (directory, library) = try CompiledFixture.build(
            libraryName: "libCleanup.dylib",
            sources: ["Cleanup.cpp": """
            #include <stdexcept>
            extern "C" __attribute__((noinline)) void cleanupCallee(void) { asm volatile(""); }
            struct Guard { ~Guard() { cleanupCallee(); } };
            __attribute__((noinline)) void mayThrow(int value) { if (value > 3) throw std::runtime_error("too large"); }
            extern "C" int withCleanup(int value) { Guard guard; mayThrow(value); return value + 1; }
            """],
            compilerArguments: ["-O1", "-lc++"],
            architecture: "arm64e"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: library)])
        let withCleanup = try #require(analyzer.functions(inImageAt: 0).first { $0.name == .symbol("_withCleanup") })
        let references = analyzer.references(madeBy: withCleanup)
        let resume = try #require(references.first { $0.target == .importedSymbol(name: "__Unwind_Resume") }, "\(references.map(\.target))")
        // The resume call comes after a return of the function's own.
        var returnAddress: UInt64?
        var address = withCleanup.location.address
        while address < resume.instructionAddress {
            if let word = analyzer.memory.load(UInt32.self, at: analyzer.imageSet.runtimeAddress(of: CodeLocation(imageIndex: 0, address: address))),
               ARM64InstructionWord.isReturn(word) {
                returnAddress = address
            }
            address += 4
        }
        #expect(returnAddress != nil, "no return before the cleanup's call at \(String(resume.instructionAddress, radix: 16))")
    }

    /// The memory decodes a shared cache's slots itself, from slide info
    /// taken once per mapping: every pointer slot of the first images of the
    /// running system's cache (slide info version 5, decoded by the memory
    /// itself) and of an iOS simulator runtime's (no slide info: MachOKit
    /// decodes them) holds what MachOKit decodes it to.
    @Test(arguments: [
        "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
        "/Volumes/DyldSharedCaches/iOS-Simulator/27.0/dyld_sim_shared_cache_arm64",
    ])
    func fileMemoryDecodesSlotsAsMachOKitDoes(cachePath: String) throws {
        guard FileManager.default.fileExists(atPath: cachePath) else {
            withKnownIssue("\(cachePath) is not on this machine") { throw CompiledFixture.Failure(description: "missing cache") }
            return
        }
        let cache = try FullDyldCache(url: URL(fileURLWithPath: cachePath))
        let storage = FileCrossReferenceMemory.storage(cache: cache)
        defer { withExtendedLifetime(storage) {} }
        let memory = FileCrossReferenceMemory(storage: storage)
        let pointerSections: Set<String> = ["__got", "__auth_got", "__objc_selrefs", "__objc_classrefs", "__objc_superrefs", "__objc_classlist", "__objc_protolist"]
        var compared = 0
        var differences: [String] = []
        for file in cache.machOFiles().prefix(60) {
            for section in file.sections64 where pointerSections.contains(section.sectionName) {
                for slot in stride(from: UInt64(section.address), to: UInt64(section.address) + UInt64(section.size), by: 8) {
                    guard let (subcache, fileOffset) = cache.cacheAndFileOffset(for: slot) else { continue }
                    let decodedByMachOKit = subcache.resolveOptionalRebase(at: fileOffset).map { UInt(truncatingIfNeeded: $0) & memory.addressMask } ?? 0
                    let decoded = memory.slotContent(at: UInt(slot))
                    if decoded != .address(decodedByMachOKit), differences.count < 5 {
                        differences.append("\(file.imagePath) \(section.sectionName) \(String(slot, radix: 16)): \(String(describing: decoded)) / MachOKit \(String(decodedByMachOKit, radix: 16))")
                    }
                    compared += 1
                }
            }
        }
        #expect(compared > 10000, "only \(compared) slots compared")
        #expect(differences.isEmpty, "\(differences)")
    }

    /// A main executable's `__TEXT` lies at 0x100000000, not at 0 as a
    /// dylib's does, so a rebase's target read as an offset from the image
    /// rather than as an address points 4 GiB below where it should: the
    /// selector references of `__objc_stubs` then lead nowhere, and every
    /// send through one reads as an unrecognized call.
    @Test func standaloneExecutableResolvesRebasesAndObjectiveCStubs() throws {
        let (directory, executable) = try CompiledFixture.build(
            libraryName: "ObjectiveCExecutable",
            sources: ["Main.m": """
            #import <Foundation/Foundation.h>
            __attribute__((noinline)) static void target(void) { asm volatile(""); }
            void (*volatile functionPointer)(void) = target;
            int main(void) {
                @autoreleasepool {
                    NSMutableArray *array = [NSMutableArray array];
                    [array addObject:@"element"];
                    functionPointer();
                    return (int)[array count];
                }
            }
            """],
            compilerArguments: ["-O1", "-fobjc-arc", "-framework", "Foundation"],
            isExecutable: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try MachOFile(url: executable)
        let analyzer = try CrossReferenceAnalyzer(machOFiles: [file])
        let main = try #require(analyzer.functions(inImageAt: 0).first { $0.name == .symbol("_main") })
        let targets = analyzer.references(madeBy: main).map(\.target)
        #expect(targets.contains { if case .messageSend("addObject:", _) = $0 { true } else { false } }, "\(targets)")
        #expect(targets.contains { if case .messageSend("count", _) = $0 { true } else { false } }, "\(targets)")
        #expect(!targets.contains { if case .unrecognized = $0 { true } else { false } }, "\(targets)")
        // A data slot rebased to a function holds the function's address.
        let dataSection = try #require(file.sections64.first { $0.segmentName == "__DATA" && $0.sectionName == "__data" })
        let slot = analyzer.memory.pointer(at: UInt(dataSection.address))
        let targetFunction = try #require(analyzer.functions(inImageAt: 0).first { $0.name == .symbol("_target") })
        #expect(slot == UInt(targetFunction.location.address), "the slot holds \(slot.map { String($0, radix: 16) } ?? "nothing")")
    }

    /// Images read from files are no `MachOImage`s; the count says how many
    /// there are.
    @Test func fileModeListsImagesByPathAndCount() throws {
        let fromFile = try #require(RunningCacheFileAnalyzer.analyzer)
        #expect(fromFile.images.isEmpty)
        #expect(fromFile.imageCount == fromFile.imagePaths.count)
        #expect(fromFile.imageCount > 1000)
        #expect(fromFile.imageIndex(forPath: "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit") != nil)
    }
}
