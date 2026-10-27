import Foundation
import Testing
import Capstone
import MachOKit
@testable import CrossReferenceAnalysis

/// One analyzer for the whole suite: building it reads every image of the
/// shared cache.
enum SharedAnalyzer {
    static let analyzer = CrossReferenceAnalyzer()
}

/// Reads the shared cache mapped into the test process. AppKit and
/// SwiftUICore are read whether or not anything loaded them — the whole
/// cache is mapped into every process.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct CrossReferenceAnalyzerTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    private func function(named name: String, inImageAt imageIndex: Int) throws -> CodeFunction {
        try #require(analyzer.functions(inImageAt: imageIndex).first { $0.name == .symbol(name) }, "no function \(name)")
    }

    @Test func knowsEveryImageOfTheSharedCache() {
        #expect(analyzer.images.count > 1000)
        #expect(analyzer.imagePaths.contains { $0.hasSuffix("/libobjc.A.dylib") })
        #expect(!analyzer.messageSendLocations.isEmpty)
        #expect(!analyzer.runtimeHelperLocations.isEmpty)
    }

    /// The three messages this method sends — through the image's own
    /// `__objc_stubs` up to macOS 26, through the stubs the cache shares
    /// from macOS 27 — each to the method's own receiver.
    @Test func objectiveCMethodSendsItsMessages() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let method = try function(named: "-[NSWindow makeKeyAndOrderFront:]", inImageAt: appKit)
        let sends = analyzer.references(madeBy: method).compactMap { reference -> (String, ReceiverClassHint, CodeReference.Kind)? in
            guard case .messageSend(let selector, let receiver) = reference.target else { return nil }
            return (selector, receiver, reference.kind)
        }
        #expect(sends.map(\.0) == ["_makeKeyRegardlessOfVisibility", "orderWindow:relativeTo:", "_enableEnablingKeyEquivalentForDefaultButtonCell"])
        let everySendGoesToTheReceiver = sends.allSatisfy { $0.1 == .methodReceiver }
        #expect(everySendGoesToTheReceiver)
        #expect(sends.map(\.2) == [.call, .call, .tailCall])
    }

    /// A classic `objc_msgSend` inside the shared cache passes the selector
    /// string's own address: the cache builder rewrote the load of the
    /// selector reference into `adrp` / `add` of the string.
    /// `-[NSObject debugDescription]` is `return [self description];`, which
    /// macOS 27.2 compiles to `adrp x8; add x1, x8; b _objc_msgSend`.
    @Test func classicSendsInsideTheCacheNameTheirSelector() throws {
        let libobjc = try imageIndex(endingWith: "/usr/lib/libobjc.A.dylib")
        let method = try function(named: "-[NSObject debugDescription]", inImageAt: libobjc)
        let sends = analyzer.references(madeBy: method).compactMap { reference -> (String, ReceiverClassHint)? in
            guard case .messageSend(let selector, let receiver) = reference.target else { return nil }
            return (selector, receiver)
        }
        #expect(sends.map(\.0) == ["description"])
        #expect(sends.first?.1 == .methodReceiver)
    }

    /// A forward branch carries what the registers hold to its target.
    /// `+[NSObject instanceMethodForSelector:]` is `cbz x2, L; …; b <tail
    /// call>; L: …; bl <send doesNotRecognizeSelector:>`: `L` is reached
    /// only from the entry, where `x0` is still the receiver. Forgetting the
    /// registers after the tail call — a shortcut tried on the way — lost
    /// that.
    @Test func branchesCarryTheirStateToTheirTargets() throws {
        let libobjc = try imageIndex(endingWith: "/usr/lib/libobjc.A.dylib")
        let method = try function(named: "+[NSObject instanceMethodForSelector:]", inImageAt: libobjc)
        let receivers = analyzer.references(madeBy: method).compactMap { reference -> ReceiverClassHint? in
            guard case .messageSend("doesNotRecognizeSelector:", let receiver) = reference.target else { return nil }
            return receiver
        }
        #expect(receivers == [.methodReceiver])
    }

    /// Two paths that reach one instruction leave a register known only
    /// when both put the same thing in it. In
    /// `-[NSString stringByAppendingString:]` one block puts the argument in
    /// `x0`, the next puts `self`, and both jump to one `copyWithZone:` send;
    /// reading straight down, as the first batch did, called its receiver
    /// `self`.
    @Test func pathsThatDisagreeLeaveTheRegisterUnknown() throws {
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let method = try function(named: "-[NSString stringByAppendingString:]", inImageAt: foundation)
        let receivers = analyzer.references(madeBy: method).compactMap { reference -> ReceiverClassHint? in
            guard case .messageSend("copyWithZone:", let receiver) = reference.target else { return nil }
            return receiver
        }
        #expect(receivers == [.unknown])
    }

    /// A Swift image's calls into the Swift runtime go through a GOT stub
    /// — the image's own `__auth_stubs` up to macOS 26, a stub the cache
    /// shares from macOS 27 — and must land on the runtime's function.
    @Test func callsThroughStubsReachTheRuntime() throws {
        let swiftUICore = try imageIndex(endingWith: "/SwiftUICore.framework/Versions/A/SwiftUICore")
        let swiftCore = try imageIndex(endingWith: "/libswiftCore.dylib")
        let table = analyzer.referenceTable(ofImageAt: swiftUICore)
        let beginAccessCalls = table.references.filter { reference in
            guard case .function(let location) = reference.target, location.imageIndex == swiftCore else { return false }
            return analyzer.symbolName(at: location) == "_swift_beginAccess"
        }
        #expect(beginAccessCalls.count > 100)
        let everyCallIsMarkedAsAHelper = beginAccessCalls.allSatisfy { $0.isRuntimeHelperCall }
        #expect(everyCallIsMarkedAsAHelper)

        let unrecognized = table.references.filter { if case .unrecognized = $0.target { true } else { false } }
        #expect(unrecognized.count * 1000 < table.references.count, "unrecognized targets: \(unrecognized.count) of \(table.references.count)")
    }

    @Test func tableGroupsReferencesByWhatTheyReference() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let table = analyzer.referenceTable(ofImageAt: appKit)
        let senders = table.references(to: .selector("orderWindow:relativeTo:"))
        let method = try function(named: "-[NSWindow makeKeyAndOrderFront:]", inImageAt: appKit)
        #expect(senders.contains { $0.function == method.location })
        #expect(table.approximateByteCount > table.references.count)
    }

    /// A query for some keys answers exactly what the whole table files under
    /// them, in the same order.
    @Test func filteredQueryMatchesTheTable() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let swiftCore = try imageIndex(endingWith: "/libswiftCore.dylib")
        let table = analyzer.referenceTable(ofImageAt: appKit)
        let beginAccess = try #require(table.keys.first { key in
            if case .function(let location) = key { location.imageIndex == swiftCore } else { false }
        })
        let keys: Set<CodeReferenceTable.Key> = [.selector("orderWindow:relativeTo:"), beginAccess]
        let filtered = analyzer.references(to: keys, inImageAt: appKit)
        let expected = table.references.filter { $0.target.tableKey.map(keys.contains) ?? false }
        #expect(!filtered.isEmpty)
        #expect(filtered == expected)
    }

    /// A cross-image query scans thousands of images; keeping the function
    /// table of each one held 1.5 GB after scanning a macOS 27.2 cache.
    @Test func wholeImageScansKeepNoFunctionTable() throws {
        let freshAnalyzer = try #require(CrossReferenceAnalyzer())
        let foundation = try #require(freshAnalyzer.imagePaths.firstIndex { $0.hasSuffix("/Foundation.framework/Versions/C/Foundation") })
        let table = freshAnalyzer.referenceTable(ofImageAt: foundation)
        #expect(!table.references.isEmpty)
        #expect(freshAnalyzer.existingFunctionTable(ofImageAt: foundation) == nil)
        // Naming functions is what keeps one.
        _ = freshAnalyzer.functions(inImageAt: foundation)
        #expect(freshAnalyzer.existingFunctionTable(ofImageAt: foundation) != nil)
    }

    /// Naming a query's results across many images keeps no function table
    /// either, and names exactly what the image's own listing names.
    @Test func namingResultsKeepsNoFunctionTable() throws {
        let freshAnalyzer = try #require(CrossReferenceAnalyzer())
        let appKit = try #require(freshAnalyzer.imagePaths.firstIndex { $0.hasSuffix("/AppKit.framework/Versions/C/AppKit") })
        let senders = freshAnalyzer.references(to: [.selector("orderWindow:relativeTo:")], inImageAt: appKit)
        let named = freshAnalyzer.functions(containing: senders.map(\.function))
        #expect(freshAnalyzer.existingFunctionTable(ofImageAt: appKit) == nil)
        #expect(named.count == Set(senders.map(\.function)).count)
        let listed = Dictionary(uniqueKeysWithValues: analyzer.functions(inImageAt: appKit).map { ($0.location, $0) })
        let namesMatchTheListing = named.allSatisfy { listed[$0.key] == $0.value }
        let namesTheSender = named.values.contains { $0.name == .symbol("-[NSWindow makeKeyAndOrderFront:]") }
        #expect(namesMatchTheListing)
        #expect(namesTheSender)
    }

    @Test func prefiltersImagesBySelectorAndImport() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let everyImage = Array(analyzer.images.indices)
        let senders = analyzer.imageIndices(referencingSelector: "orderWindow:relativeTo:", among: everyImage)
        #expect(senders.contains(appKit))
        #expect(senders.count < everyImage.count / 10)
        #expect(analyzer.imageIndices(referencingSelector: "noSuchSelectorAnywhere:forCrossReferenceTests:", among: everyImage).isEmpty)

        #expect(analyzer.imageIndices(importing: "_objc_release", among: [appKit]) == [appKit])
        #expect(analyzer.imageIndices(importing: "_noSuchFunctionForCrossReferenceTests", among: everyImage).isEmpty)
    }

    /// A prefilter may drop only images that cannot reference the subject.
    /// Every image it keeps that a scan finds sending the selector is a
    /// sender; every image it drops must be one the scan finds nothing in.
    /// From macOS 27 the sends go through stubs the cache shares, or pass the
    /// selector string's own address — the image's selector reference is what
    /// the prefilter reads, so it has to outlive both rewrites.
    ///
    /// The dropped images are sampled, every sixteenth: a Debug build scans
    /// the whole cache in minutes, not seconds.
    /// `isKindOfClass:` is sent through `objc_opt_isKindOfClass` alone, which
    /// no selector reference shows (`RuntimeSendEntryPointTests`).
    @Test(arguments: ["orderWindow:relativeTo:", "description", "count", "isKindOfClass:"])
    func selectorPrefilterKeepsEverySender(selector: String) throws {
        let everyImage = Array(analyzer.images.indices)
        let kept = analyzer.imageIndices(referencingSelector: selector, among: everyImage)
        let keys: Set<CodeReferenceTable.Key> = [.selector(selector)]
        #expect(!imagesReferencing(keys, among: Array(kept.prefix(64))).isEmpty)
        let droppedSample = Self.sample(of: Set(everyImage).subtracting(kept))
        let missed = imagesReferencing(keys, among: droppedSample)
        #expect(missed.isEmpty, "prefilter dropped senders: \(missed.sorted().prefix(5).map { analyzer.imagePaths[$0] })")
    }

    /// The same for an exported function: an image that calls it is its own
    /// or imports one of its names — even where the cache builder bound the
    /// call straight to the function.
    @Test(arguments: zip(
        ["/CoreFoundation.framework/Versions/A/CoreFoundation", "/usr/lib/system/libdispatch.dylib"],
        ["_CFRelease", "_dispatch_async"]
    ))
    func importPrefilterKeepsEveryCaller(imageSuffix: String, symbol: String) throws {
        let owner = try imageIndex(endingWith: imageSuffix)
        let function = try function(named: symbol, inImageAt: owner)
        let everyImage = Array(analyzer.images.indices)
        var kept: Set<Int> = [owner]
        for name in [symbol] + function.foldedSymbolNames {
            kept.formUnion(analyzer.imageIndices(importing: name, among: everyImage))
        }
        let keys: Set<CodeReferenceTable.Key> = [.function(function.location), .importedSymbol(symbol)]
        let importers = kept.subtracting([owner]).sorted()
        #expect(!imagesReferencing(keys, among: Array(importers.prefix(64))).isEmpty)
        let droppedSample = Self.sample(of: Set(everyImage).subtracting(kept))
        let missed = imagesReferencing(keys, among: droppedSample)
        #expect(missed.isEmpty, "prefilter dropped callers: \(missed.sorted().prefix(5).map { analyzer.imagePaths[$0] })")
    }

    /// The same for a Swift function, which few cache images import by name:
    /// only 245 of the macOS 27.2 cache's 4,113 images keep any Swift symbol
    /// among their undefined symbols, so a prefilter by imports kept the 44
    /// images importing `URL.path` and dropped every other caller. The images
    /// that can bind to Foundation are what is kept now.
    @Test func swiftFunctionPrefilterKeepsEveryCaller() throws {
        let foundation = try imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation")
        let symbol = "_$s10Foundation3URLV4pathSSvg"
        let function = try function(named: symbol, inImageAt: foundation)
        let everyImage = Array(analyzer.images.indices)
        let kept = Set(analyzer.imageIndices(callingFunctionAt: function.location, symbolNames: [symbol] + function.foldedSymbolNames, among: everyImage))
        let keys: Set<CodeReferenceTable.Key> = [.function(function.location), .importedSymbol(symbol)]
        let callers = kept.subtracting([foundation]).sorted()
        #expect(!imagesReferencing(keys, among: Array(callers.prefix(64))).isEmpty)
        let droppedSample = Self.sample(of: Set(everyImage).subtracting(kept))
        let missed = imagesReferencing(keys, among: droppedSample)
        #expect(missed.isEmpty, "prefilter dropped callers: \(missed.sorted().prefix(5).map { analyzer.imagePaths[$0] })")
    }

    /// Every sixteenth of `imageIndices`, in order.
    private static func sample(of imageIndices: Set<Int>) -> [Int] {
        imageIndices.sorted().enumerated().filter { $0.offset % 16 == 0 }.map(\.element)
    }

    /// The images among `imageIndices` with any reference to `keys`.
    private func imagesReferencing(_ keys: Set<CodeReferenceTable.Key>, among imageIndices: [Int]) -> Set<Int> {
        let found = ImageIndexCollector()
        let analyzer = analyzer
        DispatchQueue.concurrentPerform(iterations: imageIndices.count) { position in
            let imageIndex = imageIndices[position]
            if !analyzer.references(to: keys, inImageAt: imageIndex).isEmpty { found.insert(imageIndex) }
        }
        return found.indices
    }

    /// Capstone decodes the same functions independently: every call and
    /// every branch out of a function it finds, the scanner found at the
    /// same address; and every call or branch out the scanner reports is one
    /// of those, or a `br` — which Capstone cannot tell from a jump-table
    /// jump, and the scanner reports when the register was loaded from
    /// memory.
    @Test func callSitesMatchCapstone() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let functions = analyzer.functions(inImageAt: appKit)
        let disassembler = try Disassembler<AArch64>()
        let image = analyzer.images[appKit]
        let slide = try #require(image.vmaddrSlide)
        var comparedFunctionCount = 0
        var comparedBranchOutCount = 0

        for function in stride(from: 0, to: functions.count, by: max(1, functions.count / 400)).map({ functions[$0] }) where function.size >= 4 {
            let pointer = try #require(UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(function.location.address)) &+ slide))
            let code = Data(bytes: pointer, count: function.size)
            let instructions = disassembler.decode(code, address: function.location.address)
            // Capstone stops at a word it cannot decode; compare only what it read whole.
            guard instructions.count * 4 == function.size else { continue }
            comparedFunctionCount += 1

            let start = function.location.address
            let end = start + UInt64(function.size)
            var expected = Set<UInt64>()
            var registerBranches = Set<UInt64>()
            for instruction in instructions {
                switch instruction.identifier {
                case .bl, .blr, .blraa, .blraaz, .blrab, .blrabz, .braa, .braaz, .brab, .brabz:
                    expected.insert(instruction.address)
                case .br:
                    registerBranches.insert(instruction.address)
                case .b, .cbz, .cbnz, .tbz, .tbnz, .bc:
                    let operandIndex = instruction.identifier == .tbz || instruction.identifier == .tbnz ? 2 : (instruction.identifier == .cbz || instruction.identifier == .cbnz ? 1 : 0)
                    if operandIndex < instruction.operands.count,
                       let target = instruction.operands[operandIndex].immediateValue.map({ UInt64(bitPattern: $0) }), target < start || target >= end {
                        expected.insert(instruction.address)
                        comparedBranchOutCount += 1
                    }
                default:
                    break
                }
            }
            // Type references sit on `adrp`, `add` and `ldr`; only calls and
            // branches out are compared.
            let found = Set(analyzer.references(madeBy: function).filter { $0.kind != .reference }.map(\.instructionAddress))
            let missing = expected.subtracting(found)
            #expect(missing.isEmpty, "\(function.name.map { "\($0)" } ?? "unnamed") at 0x\(String(start, radix: 16)): missing \(missing.sorted().map { String($0, radix: 16) })")
            let extra = found.subtracting(expected).subtracting(registerBranches)
            #expect(extra.isEmpty, "\(function.name.map { "\($0)" } ?? "unnamed") at 0x\(String(start, radix: 16)): no call at \(extra.sorted().map { String($0, radix: 16) })")
        }
        #expect(comparedFunctionCount > 100)
        // Without operands this half of the comparison would silently compare nothing.
        #expect(comparedBranchOutCount > 1)
    }
}

/// Image indices gathered from concurrent scans.
final class ImageIndexCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = Set<Int>()

    func insert(_ imageIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        collected.insert(imageIndex)
    }

    var indices: Set<Int> {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}
