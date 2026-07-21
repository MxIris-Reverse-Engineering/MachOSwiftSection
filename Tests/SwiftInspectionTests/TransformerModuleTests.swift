import Foundation
import Testing
import OutputTransformer

/// Unit tests for the Swift transformer modules that moved library-side from
/// RuntimeViewerCore: rendering behavior, the Swift configuration aggregate,
/// and the persistence contract (RuntimeViewer decodes stored settings through
/// these types, so decoding must tolerate missing keys and keep the historical
/// key names). The ObjC-side modules (`CType`, `ObjCIvarOffset`) stay in
/// RuntimeViewerCore for now and are tested there.
@Suite
struct TransformerModuleTests {

    // MARK: - Simple token modules

    @Test func fieldOffsetRendersRangeAndHandlesMissingEndOffset() {
        var module = Transformer.SwiftFieldOffset(isEnabled: true)
        #expect(module.transform(.init(startOffset: 16, endOffset: 24)) == "Field Offset: 0x10")
        module.template = Transformer.SwiftFieldOffset.Templates.range
        #expect(module.transform(.init(startOffset: 16, endOffset: 24)) == "0x10 ..< 0x18")
        #expect(module.transform(.init(startOffset: 16, endOffset: nil)) == "0x10 ..< ?")
        module.useHexadecimal = false
        #expect(module.transform(.init(startOffset: 16, endOffset: 24)) == "16 ..< 24")
    }

    @Test func memberAddressRendersHexByDefault() {
        let module = Transformer.SwiftMemberAddress(isEnabled: true)
        #expect(module.transform(.init(offset: 0x1234)) == "Address: 0x1234")
    }

    @Test func vtableOffsetPicksLabeledTemplateWhenLabelPresent() {
        let module = Transformer.SwiftVTableOffset(isEnabled: true)
        #expect(module.transform(.init(slotOffset: 42, label: nil)) == "VTable Offset: 42")
        #expect(module.transform(.init(slotOffset: 42, label: "getter")) == "VTable Offset (getter): 42")
    }

    @Test func typeLayoutRendersStandardAndUnknownFlags() {
        var module = Transformer.SwiftTypeLayout(isEnabled: true)
        let fullInput = Transformer.SwiftTypeLayout.Input(
            size: 9, stride: 16, alignment: 8, extraInhabitantCount: 0,
            isPOD: true, isInlineStorage: true, isBitwiseTakable: true,
            isBitwiseBorrowable: true, isCopyable: true, hasEnumWitnesses: false, isIncomplete: false
        )
        #expect(module.transform(fullInput) == "Type Layout: (size: 9, stride: 16, alignment: 8, extraInhabitantCount: 0)")
        // A caller that cannot know the value-witness flags (the static
        // offline path) passes nil — the tokens render as "unknown".
        module.template = "${size}/${isPOD}/${isBitwiseTakable}"
        let partialInput = Transformer.SwiftTypeLayout.Input(
            size: 9, stride: 16, alignment: 8, extraInhabitantCount: 0, isBitwiseTakable: true
        )
        #expect(module.transform(partialInput) == "9/unknown/true")
    }

    // MARK: - Swift configuration aggregate

    @Test func defaultConfigurationHasNoEnabledModules() {
        #expect(!Transformer.SwiftConfiguration().hasEnabledModules)
        var configuration = Transformer.SwiftConfiguration()
        configuration.swiftEnumLayout.isEnabled = true
        #expect(configuration.hasEnabledModules)
    }

    // MARK: - Persistence contract

    @Test func configurationCodableRoundTrip() throws {
        var configuration = Transformer.SwiftConfiguration()
        configuration.swiftFieldOffset = .init(isEnabled: true, template: "custom ${startOffset}", useHexadecimal: false)
        configuration.swiftEnumLayout = .explained
        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(Transformer.SwiftConfiguration.self, from: encoded)
        #expect(decoded == configuration)
    }

    /// Stored settings from older versions may lack any key (the historical
    /// MetaCodable `@Default(ifMissing:)` contract): every level must decode
    /// from an empty object into its defaults.
    @Test func decodingToleratesMissingKeys() throws {
        let decoder = JSONDecoder()
        let emptyObject = Data("{}".utf8)
        let configuration = try decoder.decode(Transformer.SwiftConfiguration.self, from: emptyObject)
        #expect(configuration == Transformer.SwiftConfiguration())
        let enumModule = try decoder.decode(Transformer.SwiftEnumLayout.self, from: emptyObject)
        #expect(enumModule.isEnabled == false)
        #expect(enumModule.appendsOmittedDetails == true)
        let partial = Data(#"{"isEnabled": true}"#.utf8)
        let partialModule = try decoder.decode(Transformer.SwiftFieldOffset.self, from: partial)
        #expect(partialModule.isEnabled == true)
        #expect(partialModule.template == Transformer.SwiftFieldOffset.Templates.standard)
    }
}
