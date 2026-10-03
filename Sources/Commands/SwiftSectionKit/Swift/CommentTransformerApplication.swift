import OutputTransformer
import SwiftOutputTransformer
import SwiftDeclarationRendering
import SwiftPrinting

extension Transformer.SwiftConfiguration {
    /// The comment kinds the enabled modules render. A module is only reached
    /// once its comment kind is emitted, so enabling one implies emitting it —
    /// passing a template is enough to see its output.
    package struct CommentFlags {
        package var printFieldOffset = false
        package var printVTableOffset = false
        package var printMemberAddress = false
        package var printTypeLayout = false
        package var printEnumLayout = false
    }

    package var commentFlagsForEnabledModules: CommentFlags {
        .init(
            printFieldOffset: swiftFieldOffset.isEnabled,
            printVTableOffset: swiftVTableOffset.isEnabled,
            printMemberAddress: swiftMemberAddress.isEnabled,
            printTypeLayout: swiftTypeLayout.isEnabled,
            printEnumLayout: swiftEnumLayout.isEnabled
        )
    }
}

extension DeclarationRenderConfiguration {
    /// Applies `transformers` and turns on the comment kinds its enabled
    /// modules render, leaving every already-requested comment kind on.
    package mutating func applyTransformersEnablingCommentKinds(_ transformers: Transformer.SwiftConfiguration) {
        let commentFlags = transformers.commentFlagsForEnabledModules
        printFieldOffset = printFieldOffset || commentFlags.printFieldOffset
        printVTableOffset = printVTableOffset || commentFlags.printVTableOffset
        printMemberAddress = printMemberAddress || commentFlags.printMemberAddress
        printTypeLayout = printTypeLayout || commentFlags.printTypeLayout
        printEnumLayout = printEnumLayout || commentFlags.printEnumLayout
        applyTransformers(transformers)
    }
}

extension SwiftDeclarationPrintConfiguration {
    /// Applies `transformers` and turns on the comment kinds its enabled
    /// modules render, leaving every already-requested comment kind on.
    package mutating func applyTransformersEnablingCommentKinds(_ transformers: Transformer.SwiftConfiguration) {
        let commentFlags = transformers.commentFlagsForEnabledModules
        printFieldOffset = printFieldOffset || commentFlags.printFieldOffset
        printVTableOffset = printVTableOffset || commentFlags.printVTableOffset
        printMemberAddress = printMemberAddress || commentFlags.printMemberAddress
        printTypeLayout = printTypeLayout || commentFlags.printTypeLayout
        printEnumLayout = printEnumLayout || commentFlags.printEnumLayout
        applyTransformers(transformers)
    }
}
