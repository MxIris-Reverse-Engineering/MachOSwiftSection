import Foundation
import Testing
import MachOKit
import MachOKitExtensions
import CrossReferenceAnalysis
import SwiftSectionKit

/// `refs` and `symbolicate` as a host runs them: over the running system's
/// dyld shared cache read from its files, an archived cache, and a
/// standalone app executable.
@Suite(.enabled(if: FullDyldCache.cachedHost != nil, "needs the running system's dyld shared cache"))
struct CrossReferenceRequestTests {
    static let archivedCachePath = "/Volumes/DyldSharedCaches/macOS/27.2/dyld_shared_cache_arm64e"
    static let selector = "makeKeyAndOrderFront:"

    private static func isSend(_ target: CodeReferenceTarget, of selector: String) -> Bool {
        switch target {
        case .messageSend(selector, _), .superMessageSend(selector, _): true
        default: false
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: archivedCachePath), "needs the archived macOS 27.2 cache"))
    func refsListsCallerRowsForASelectorInAnArchivedCache() async throws {
        let output = RecordingOutput()
        let result = try await ReferencesRequest(input: .dyldSharedCache(path: Self.archivedCachePath), subject: .selector(Self.selector)).run(output: output)
        #expect(result.rows.count > 100)
        #expect(!result.isTruncated)
        #expect(result.rows.allSatisfy { Self.isSend($0.reference.target, of: Self.selector) })
        #expect(result.rows.contains { $0.imagePath.hasSuffix("/AppKit.framework/Versions/C/AppKit") })
        let lines = output.printedProduct.split(separator: "\n")
        #expect(lines.count == result.rows.count)
        #expect(lines.allSatisfy { $0.hasPrefix("0x") && $0.contains(" \(Self.selector)") })
        #expect(output.messages(of: .note).count == 1)
    }

    @Test func refsJSONUsesHexadecimalStringAddresses() async throws {
        let output = RecordingOutput()
        try await ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), imageNames: ["AppKit"], limit: 5, format: .json).run(output: output)
        guard case .data(let data)? = output.products.first, output.products.count == 1 else {
            Issue.record("expected one JSON document, got \(output.products.count) pieces")
            return
        }
        let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((document["query"] as? [String: Any])?["selector"] as? String == Self.selector)
        #expect(document["isTruncated"] as? Bool == true)
        #expect((document["scannedImageCount"] as? Int).map { $0 >= 1 } == true)
        #expect(((document["input"] as? [String: Any])?["imageCount"] as? Int).map { $0 > 1000 } == true)
        let references = try #require(document["references"] as? [[String: Any]])
        #expect(references.count == 5)
        for reference in references {
            let site = try #require(reference["site"] as? String)
            #expect(site.hasPrefix("0x"))
            let function = try #require(reference["function"] as? [String: Any])
            #expect((function["address"] as? String)?.hasPrefix("0x") == true)
            #expect((reference["image"] as? String)?.hasSuffix("/AppKit") == true)
            #expect(["call", "tailCall"].contains(reference["kind"] as? String))
            let target = try #require(reference["target"] as? [String: Any])
            let send = (target["messageSend"] ?? target["superMessageSend"]) as? [String: Any]
            #expect(send?["selector"] as? String == Self.selector)
        }
    }

    @Test func refsMarksTruncatedResultsWhenLimited() async throws {
        let request = ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), imageNames: ["AppKit"])
        let whole = try await request.run(output: RecordingOutput())
        #expect(whole.rows.count > 1)
        #expect(!whole.isTruncated)

        var limited = request
        limited.limit = 1
        let output = RecordingOutput()
        let truncated = try await limited.run(output: output)
        #expect(truncated.isTruncated)
        #expect(truncated.rows == Array(whole.rows.prefix(1)))
        #expect(output.printedProduct.split(separator: "\n").count == 1)
        #expect(output.messages(of: .note).first?.contains("the first 1 of \(whole.rows.count)") == true)

        limited.limit = whole.rows.count
        #expect(try await !limited.run(output: RecordingOutput()).isTruncated)
    }

    @Test func refsListsTheCalleesOfAFunction() async throws {
        let callers = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), imageNames: ["AppKit"], limit: 1).run(output: RecordingOutput())
        let caller = try #require(callers.rows.first)
        let callees = try await ReferencesRequest(
            input: .systemDyldSharedCache,
            subject: .function(address: caller.reference.function.address, imageName: nil),
            direction: .callees
        ).run(output: RecordingOutput())
        #expect(callees.scannedImageCount == 1)
        #expect(callees.rows.contains { $0.reference == caller.reference })
        #expect(callees.rows.allSatisfy { $0.reference.function == caller.reference.function })
    }

    /// The callers of `objc_autoreleasePoolPush` AppKit holds: it calls the
    /// function libobjc defines.
    @Test func refsListsTheCallersOfASymbol() async throws {
        let result = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .symbol("_objc_autoreleasePoolPush"), imageNames: ["AppKit"]).run(output: RecordingOutput())
        #expect(!result.rows.isEmpty)
        #expect(result.rows.allSatisfy { $0.imagePath.hasSuffix("/AppKit") && $0.reference.kind != .reference })
        let callee = try #require(result.rows.first.flatMap { row -> CodeLocation? in
            if case .function(let location) = row.reference.target { location } else { nil }
        })
        let symbolications = try await SymbolicateRequest(input: .systemDyldSharedCache, addresses: [callee.address]).run(output: RecordingOutput())
        guard case .function(_, let name, 0)? = symbolications.first?.meaning else {
            Issue.record("\(String(describing: symbolications.first))")
            return
        }
        #expect(name == "_objc_autoreleasePoolPush")
    }

    @Test func refsListsTheReferencesToAClass() async throws {
        let result = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .objectiveCClass("NSWindow"), imageNames: ["AppKit"]).run(output: RecordingOutput())
        #expect(!result.rows.isEmpty)
        #expect(result.rows.allSatisfy { row in
            if case .objectiveCClass("NSWindow", _) = row.reference.target { true } else { false }
        })
        // The class symbol is the same subject.
        let bySymbol = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .symbol("_OBJC_CLASS_$_NSWindow"), imageNames: ["AppKit"]).run(output: RecordingOutput())
        #expect(bySymbol.rows == result.rows)
    }

    @Test func refsRejectsAnImageNoAnalyzedImageHas() async throws {
        await #expect(throws: CrossReferenceRequestError.imageNotFound(name: "NoSuchImage")) {
            try await ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), imageNames: ["NoSuchImage"]).run(output: RecordingOutput())
        }
        await #expect(throws: CrossReferenceRequestError.symbolNotFound(name: "_NoSuchSymbolAnywhere")) {
            try await ReferencesRequest(input: .systemDyldSharedCache, subject: .symbol("_NoSuchSymbolAnywhere"), imageNames: ["AppKit"]).run(output: RecordingOutput())
        }
        await #expect(throws: CrossReferenceRequestError.calleesRequireFunction) {
            try await ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), direction: .callees).run(output: RecordingOutput())
        }
    }

    /// A standalone, fat app executable: the slice named is read, its sends
    /// are found in it alone — and without a slice named, none is picked.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"), "needs TextEdit"))
    func refsReadsAStandaloneFatExecutable() async throws {
        let path = "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
        let result = try await ReferencesRequest(input: .files(paths: [path], architecture: .arm64e), subject: .selector("init")).run(output: RecordingOutput())
        #expect(!result.rows.isEmpty)
        #expect(result.scannedImageCount == 1)
        #expect(result.rows.allSatisfy { $0.imagePath == path && Self.isSend($0.reference.target, of: "init") })
        await #expect(performing: {
            try await ReferencesRequest(input: .files(paths: [path], architecture: nil), subject: .selector("init")).run(output: RecordingOutput())
        }, throws: { error in
            if case MachOSourceError.fatBinaryRequiresArchitecture = error { true } else { false }
        })
    }

    @Test func symbolicateAcceptsSeveralAddresses() async throws {
        let callers = try await ReferencesRequest(input: .systemDyldSharedCache, subject: .selector(Self.selector), imageNames: ["AppKit"], limit: 1).run(output: RecordingOutput())
        let reference = try #require(callers.rows.first?.reference)
        let addresses = [reference.instructionAddress, reference.function.address, 0x10]
        let output = RecordingOutput()
        let symbolications = try await SymbolicateRequest(input: .systemDyldSharedCache, addresses: addresses).run(output: output)
        #expect(symbolications.map(\.address) == addresses)
        #expect(symbolications[0].meaning.functionStart == reference.function.address)
        #expect(symbolications[0].meaning.functionOffset == reference.instructionAddress - reference.function.address)
        #expect(symbolications[1].meaning.functionOffset == 0)
        #expect(symbolications[2].meaning == .unmapped)
        #expect(symbolications[0].imagePath?.hasSuffix("/AppKit") == true)
        let lines = output.printedProduct.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[2] == "0x10  -  -  unmapped")
        #expect(lines[0].hasPrefix(String(format: "0x%llx  AppKit  __TEXT,__text  ", reference.instructionAddress)))
    }

    @Test func symbolicateJSONUsesHexadecimalStringAddresses() async throws {
        let output = RecordingOutput()
        try await SymbolicateRequest(input: .systemDyldSharedCache, addresses: [0x10], format: .json).run(output: output)
        guard case .data(let data)? = output.products.first else {
            Issue.record("expected a JSON document")
            return
        }
        let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let symbolications = try #require(document["symbolications"] as? [[String: Any]])
        #expect(symbolications.count == 1)
        #expect(symbolications.first?["address"] as? String == "0x10")
        #expect((symbolications.first?["meaning"] as? [String: Any])?["unmapped"] != nil)
    }
}

extension AddressSymbolication.Meaning {
    fileprivate var functionStart: UInt64? {
        if case .function(let start, _, _) = self { start.address } else { nil }
    }

    fileprivate var functionOffset: UInt64? {
        if case .function(_, _, let offset) = self { offset } else { nil }
    }
}
