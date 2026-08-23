#if os(macOS)

import Testing
@testable import TypeIndexing

@Suite
struct ImportScanTests {
    @Test
    func plainAndAttributedImportsAreCollectedInOrder() {
        let sourceText = """
        import Foundation
        @_exported import ObjectiveC
        public import CoreGraphics
        """
        #expect(SourceKitManager.importedModuleNames(inInterfaceSourceText: sourceText) == [
            "Foundation",
            "ObjectiveC",
            "CoreGraphics",
        ])
    }

    @Test
    func subModuleImportsKeepTheirDottedSpelling() {
        let sourceText = """
        import Foundation.NSObject
        import Foundation.NSString
        """
        #expect(SourceKitManager.importedModuleNames(inInterfaceSourceText: sourceText) == [
            "Foundation.NSObject",
            "Foundation.NSString",
        ])
    }

    @Test
    func duplicatesCommentsAndNonImportLinesAreIgnored() {
        let sourceText = """
        // import CommentedOut
        import Foundation
        import Foundation
        let importCount = 1
        func doSomething() { }
        """
        #expect(SourceKitManager.importedModuleNames(inInterfaceSourceText: sourceText) == ["Foundation"])
    }

    @Test
    func importAppearingAfterNonModifierTokensIsRejected() {
        let sourceText = """
        let value = import Foundation
        """
        #expect(SourceKitManager.importedModuleNames(inInterfaceSourceText: sourceText).isEmpty)
    }
}

#endif
