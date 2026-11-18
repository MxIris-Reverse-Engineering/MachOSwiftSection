import Testing
import CrossReferenceAnalysis

/// The types the layers below the Swift one define stay part of
/// `CrossReferenceAnalysis`'s public face: a host that imports only it —
/// RuntimeViewer — spells them as before the split. A plain import, not a
/// testable one, so that this file fails to compile when one goes missing.
@Suite
struct PublicNameTests {
    @Test func publicNamesStillResolveThroughCrossReferenceAnalysis() {
        let location = CodeLocation(imageIndex: 1, address: 0x1000)
        let kind: CodeReference.Kind = .call
        let receiver: ReceiverClassHint = .methodReceiver
        let evidence = IndirectCallEvidence(table: .none, tableOffset: 8, pointerAuthenticationConstant: nil, isAddressBlended: false)
        let reference = CodeReference(function: location, instructionAddress: 0x1004, kind: kind, target: .messageSend(selector: "init", receiver: receiver), isRuntimeHelperCall: false)
        #expect(reference.kind == .call)
        #expect(reference.target.tableKey == .selector("init"))
        #expect(CodeReferenceTarget.indirect(evidence).tableKey == nil)
    }
}
