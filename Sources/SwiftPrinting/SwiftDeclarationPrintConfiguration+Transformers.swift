import Foundation
import SemanticTransformer
import SwiftDeclarationRendering

extension SwiftDeclarationPrintConfiguration {
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
