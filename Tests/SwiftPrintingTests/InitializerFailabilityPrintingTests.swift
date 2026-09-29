@_spi(Support) @testable import SwiftPrinting
import Demangling
import Testing

/// An initializer is failable when ITS OWN result is `Optional<Self>` — not
/// when an Optional appears somewhere else in its signature.
///
/// The failability check used to search the whole symbol tree for the first
/// `returnType` node, and a closure parameter's return type comes before the
/// initializer's own in that walk. That went wrong both ways: AppKit's
/// non-failable `NSCollectionViewDiffableDataSource.init(collectionView:itemProvider:)`,
/// whose item provider returns `NSCollectionViewItem?`, printed as `init?`,
/// and SwiftUI's failable `CoreDisplayLink.init?(displayID:handler:)`, whose
/// handler returns `()`, printed as `init`.
///
/// An initializer declared on `Optional` itself is the one place where an
/// Optional result is not failability: `Optional<Wrapped>` is its Self, and
/// only a failable one returns `Optional<Optional<Wrapped>>`.
@Suite
struct InitializerFailabilityPrintingTests {
    @Test(arguments: [
        // Non-failable; the closure parameter returns an Optional.
        ("$s4Main3FooC4makeACSiSgyc_tcfC", "init(make: "),
        // The same inside a generic context, where the function type sits
        // under a dependent generic signature.
        ("$s4Main3BarV4makeACyxGxSgyXE_tcfC", "init(make: "),
        // The real-world case.
        ("$s6AppKit34NSCollectionViewDiffableDataSourceC010collectionD012itemProviderACyxq_GSo0cD0C_So0cD4ItemCSgAH_10Foundation9IndexPathVq_tctcfC", "init(collectionView: "),
        // Non-failable; a plain Optional parameter.
        ("$s4Main3FooC8optionalACSiSg_tcfC", "init(optional: "),
        // Failable.
        ("$s4Main3FooC5valueACSgSi_tcfC", "init?(value: "),
        // Failable, and the closure parameter returns an Optional as well.
        ("$s4Main3FooC9transformACSgSSSgSic_tcfC", "init?(transform: "),
        // Failable, and the closure parameter returns something else first.
        ("$s7SwiftUI15CoreDisplayLinkC9displayID7handlerACSgs6UInt32V_yAC_SdtctcfC", "init?(displayID: "),
        // Declared on `Optional`: `Wrapped?` is Self, so not failable —
        // directly on the type and in an extension of it (SwiftUI's
        // `init(if:then:)` has this shape).
        ("$sSqyxSgxcfC", "init("),
        ("$sSq13OptionalProbeE2if4thenxSgSb_xyXKtcfC", "init(if: "),
        // Declared on `Optional` and failable: `Wrapped??`.
        ("$sSq13OptionalProbeE7failingxSgSgSi_tcfC", "init?(failing: "),
    ])
    func failabilityFollowsTheInitializersOwnResult(mangledName: String, expectedPrefix: String) async throws {
        let node = try await demangleAsNode(mangledName)
        var printer = SemanticFunctionNodePrinter(isOverride: false)
        let declaration = try await printer.printRoot(node).string
        #expect(declaration.hasPrefix(expectedPrefix), "\(declaration)")
    }
}
