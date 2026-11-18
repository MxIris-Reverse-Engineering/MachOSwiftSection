import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// The core's scan takes any recognizer: a language layer is one more
/// session, and the core does not change (evolution proposal
/// `offline-cross-references-and-symbolication`).
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct RecognizerExtensionPointTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    /// A session no layer of the library knows: it stands in for every call
    /// into one image.
    private final class CallsIntoImageSession: CodeReferenceRecognitionSession {
        let recognizedImageIndex: Int
        let recording: Recording

        init(recognizedImageIndex: Int, recording: Recording) {
            self.recognizedImageIndex = recognizedImageIndex
            self.recording = recording
        }

        var referenceSlotRanges: [Range<UInt64>] { [] }
        var watchedSlotRanges: [Range<UInt64>] { [] }
        var looksForAddressReferences: Bool { false }
        func enterFunction(at functionIndex: Int, registers: RegisterFile) {}
        func claimCallTarget(at target: UInt64) -> CallTargetClaim? { nil }

        func role(of target: ResolvedCallTarget) -> CalleeRole? {
            guard case .function(let location) = target, location.imageIndex == recognizedImageIndex else { return nil }
            return CalleeRole(code: 1, mayStandIn: true, notesCallMade: false)
        }

        func recordCallStandIn(_ call: ScannedCall, registers: RegisterFile) -> Bool {
            recording.stoodInCallCount += 1
            return true
        }

        func noteCallMade(_ call: ScannedCall, registers: RegisterFile) -> UInt32 { 0 }
        func recordAddressReference(toRuntimeAddress address: UInt, isCode: Bool, at site: ScanSite) -> Bool { false }
        func recordSlotReference(holding value: UInt, at site: ScanSite) -> Bool { false }
        func noteWatchedSlotLoad(from slot: UInt64) {}
    }

    private final class Recording: CodeReferenceRecording {
        let recognizedImageIndex: Int
        var stoodInCallCount = 0
        var plainCallsIntoTheImage = 0
        var plainCallCount = 0

        init(recognizedImageIndex: Int) {
            self.recognizedImageIndex = recognizedImageIndex
        }

        func recordCall(to target: ResolvedCallTarget, targetAddress: UInt64, at site: ScanSite, isRuntimeHelperCall: Bool) {
            plainCallCount += 1
            if case .function(let location) = target, location.imageIndex == recognizedImageIndex { plainCallsIntoTheImage += 1 }
        }

        func recordIndirectCall(_ evidence: IndirectCallEvidence, at site: ScanSite) {}
    }

    @Test func aRecognizerDefinedInTestsPlugsInWithoutChangingTheCore() throws {
        let foundation = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/Foundation.framework/Versions/C/Foundation") })
        let libobjc = try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix("/libobjc.A.dylib") })
        let recording = Recording(recognizedImageIndex: libobjc)
        let table = analyzer.imageSet.transientFunctionTable(ofImageAt: foundation)
        var scanner = ReferenceScanner(
            images: analyzer.imageSet,
            table: table,
            sessions: [CallsIntoImageSession(recognizedImageIndex: libobjc, recording: recording)],
            recording: recording
        )
        for index in table.starts.indices {
            scanner.scanFunction(at: index)
        }
        // Foundation calls libobjc all the time — `objc_msgSend` among it —
        // and every such call went to the session instead of the core.
        #expect(recording.stoodInCallCount > 10000)
        #expect(recording.plainCallsIntoTheImage == 0)
        #expect(recording.plainCallCount > 10000)
    }

    /// A query for the senders of a selector looks up no Swift type: the
    /// Swift session skips its accessors, metadata and mangled names when the
    /// query keeps none of them.
    @Test func selectorQueriesLookUpNoSwiftType() throws {
        let freshAnalyzer = try #require(CrossReferenceAnalyzer())
        let swiftUICore = try #require(freshAnalyzer.imagePaths.firstIndex { $0.hasSuffix("/SwiftUICore.framework/Versions/A/SwiftUICore") })
        let sends = freshAnalyzer.references(to: [.selector("init")], inImageAt: swiftUICore)
        #expect(!sends.isEmpty)
        let builtTypeIndexes = freshAnalyzer.imagePaths.indices.filter { freshAnalyzer.existingIndexes(ofImageAt: $0).swiftTypeIndex != nil }
        #expect(builtTypeIndexes.isEmpty, "type indexes built for \(builtTypeIndexes.map { freshAnalyzer.imagePaths[$0] })")
    }
}
