import Foundation
import Testing
import OutputTransformer
@testable import SwiftOutputTransformer

@Suite("Swift output transformer")
struct SwiftOutputTransformerTests {
    @Test("Modules extend the shared Transformer namespace")
    func modulesExtendSharedNamespace() {
        #expect(Transformer.SwiftEnumLayout.displayName == "Enum Layout Comment")
        #expect(!Transformer.SwiftEnumLayout.CaseTemplates.all.isEmpty)
    }

    @Test("Enabled modules render their templates")
    func enabledModulesRenderTemplates() {
        var fieldOffsetModule = Transformer.SwiftFieldOffset(isEnabled: true)
        fieldOffsetModule.template = Transformer.SwiftFieldOffset.Templates.range
        #expect(fieldOffsetModule.transform(.init(startOffset: 0, endOffset: 8)) == "0x0 ..< 0x8")

        let compactEnumModule = Transformer.SwiftEnumLayout.compact
        let caseInput = Transformer.SwiftEnumLayout.CaseInput(
            caseIndex: 1,
            caseName: "payload case #1",
            declaredName: "value",
            isPayloadCase: true,
            tagValue: 1,
            payloadValue: 0
        )
        #expect(compactEnumModule.transformCase(caseInput) == "[0x01] `value` — payload case, tag 1")
    }

    @Test("SwiftConfiguration tolerates missing keys and reports enablement")
    func swiftConfigurationDecodingAndEnablement() throws {
        let decoded = try JSONDecoder().decode(
            Transformer.SwiftConfiguration.self,
            from: Data("{}".utf8)
        )
        #expect(decoded == .init())
        #expect(!decoded.hasEnabledModules)

        var configuration = Transformer.SwiftConfiguration()
        configuration.swiftTypeLayout.isEnabled = true
        #expect(configuration.hasEnabledModules)
    }
}
