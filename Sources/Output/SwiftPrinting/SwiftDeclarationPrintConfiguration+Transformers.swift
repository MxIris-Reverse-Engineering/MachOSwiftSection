import Foundation
import OutputTransformer
import SwiftOutputTransformer
import ObjCOutputTransformer
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

    /// Installs what the Objective-C transformer modules change in a Swift
    /// print: the replacements of an enabled `cType` module, for the types
    /// the interface reads off the Objective-C side (evolution proposal
    /// `objc-ivar-type-recovery`), so both sides of a class spell a C
    /// primitive alike. A disabled module clears them.
    public mutating func applyTransformers(_ transformers: Transformer.ObjCConfiguration) {
        cTypeReplacements = transformers.cType.isEnabled ? transformers.cType.replacements.filter { !$0.value.isEmpty } : [:]
    }
}
