import Foundation
import Semantic
import OutputTransformer
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

/// Materializes enabled `Transformer` modules into the closure-transformer
/// slots the render/print configurations consume — the wiring RuntimeViewer
/// used to carry, now library-side so every consumer applies a
/// `Transformer.SwiftConfiguration` with one call and RuntimeViewer keeps only
/// the settings UI.
extension Transformer.SwiftConfiguration {
    /// The member-address closure for the enabled module, `nil` when disabled
    /// (the built-in rendering applies).
    public func makeMemberAddressTransformer() -> MemberAddressTransformer? {
        guard swiftMemberAddress.isEnabled else { return nil }
        let module = swiftMemberAddress
        return MemberAddressTransformer { offset in
            Comment(module.transform(.init(offset: offset))).asSemanticString()
        }
    }

    /// The vtable-offset closure for the enabled module, `nil` when disabled.
    public func makeVTableOffsetTransformer() -> VTableOffsetTransformer? {
        guard swiftVTableOffset.isEnabled else { return nil }
        let module = swiftVTableOffset
        return VTableOffsetTransformer { input in
            Comment(module.transform(.init(slotOffset: input.slotOffset, label: input.label))).asSemanticString()
        }
    }

    /// The field-offset closure for the enabled module, `nil` when disabled.
    public func makeFieldOffsetTransformer() -> FieldOffsetTransformer? {
        guard swiftFieldOffset.isEnabled else { return nil }
        let module = swiftFieldOffset
        return FieldOffsetTransformer { input in
            Comment(module.transform(.init(startOffset: input.startOffset, endOffset: input.endOffset))).asSemanticString()
        }
    }

    /// The type-layout closure for the enabled module, `nil` when disabled.
    /// Typed on the runtime `TypeLayout` (all value-witness flags known), so
    /// it applies to the runtime / `MachOImage` path.
    public func makeTypeLayoutTransformer() -> TypeLayoutTransformer? {
        guard swiftTypeLayout.isEnabled else { return nil }
        let module = swiftTypeLayout
        return TypeLayoutTransformer { typeLayout in
            let input = Transformer.SwiftTypeLayout.Input(
                size: Int(typeLayout.size),
                stride: Int(typeLayout.stride),
                alignment: Int(typeLayout.flags.alignment),
                extraInhabitantCount: Int(typeLayout.extraInhabitantCount),
                isPOD: typeLayout.flags.isPOD,
                isInlineStorage: typeLayout.flags.isInlineStorage,
                isBitwiseTakable: typeLayout.flags.isBitwiseTakable,
                isBitwiseBorrowable: typeLayout.flags.isBitwiseBorrowable,
                isCopyable: typeLayout.flags.isCopyable,
                hasEnumWitnesses: typeLayout.flags.hasEnumWitnesses,
                isIncomplete: typeLayout.flags.isIncomplete
            )
            return Comment(module.transform(input)).asSemanticString()
        }
    }

    /// The enum-layout strategy-line and per-case closures for the enabled
    /// module, `(nil, nil)` when disabled.
    public func makeEnumLayoutTransformers() -> (EnumLayoutTransformer?, EnumLayoutCaseTransformer?) {
        guard swiftEnumLayout.isEnabled else { return (nil, nil) }
        let module = swiftEnumLayout
        let layoutTransformer = EnumLayoutTransformer { layoutResult in
            InlineComment(module.renderStrategyComment(for: layoutResult)).asSemanticString()
        }
        let caseTransformer = EnumLayoutCaseTransformer { input in
            AtomicComponent(
                string: input.caseProjection.description(indent: input.indentation, prefix: "//", template: module),
                type: .comment
            ).asSemanticString()
        }
        return (layoutTransformer, caseTransformer)
    }
}

extension DeclarationRenderConfiguration {
    /// Installs the enabled modules of `transformers` into this
    /// configuration's closure-transformer slots (and clears the slots of
    /// disabled modules back to the built-in rendering). Custom closures
    /// previously assigned to those slots are replaced.
    public mutating func applyTransformers(_ transformers: Transformer.SwiftConfiguration) {
        memberAddressTransformer = transformers.makeMemberAddressTransformer()
        vtableOffsetTransformer = transformers.makeVTableOffsetTransformer()
        fieldOffsetTransformer = transformers.makeFieldOffsetTransformer()
        typeLayoutTransformer = transformers.makeTypeLayoutTransformer()
        (enumLayoutTransformer, enumLayoutCaseTransformer) = transformers.makeEnumLayoutTransformers()
    }
}
