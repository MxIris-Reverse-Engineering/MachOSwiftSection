import Foundation
import MachOFixtureSupport
import MachOKit
import MachOKitExtensions
import MachODependencies
import Testing
@testable import MachOTestingSupport
@testable import SwiftInterface

/// Pins what `SwiftInterfaceBuilderDependencies` promises now that it is a
/// thin wrapper over `DependencyClosure` (evolution proposal
/// macho-dependencies-module): direct-only semantics for both readers,
/// and an image initializer that actually resolves something.
///
/// Declares `SymbolTestsHelper` for the same reason `DependencyClosureTests`
/// does: the image initializer resolves the fixture's `@rpath` sibling through
/// `MachOImage(name:)`. Nothing here indexes it or touches a per-image cache —
/// the declaration is what makes the sharing greppable, as AGENTS.md asks of
/// every suite touching that image.
@Suite(ExclusiveImageAccess(.SymbolTestsHelper))
final class SwiftInterfaceBuilderDependenciesTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func bareImageNames<MachO: MachORepresentableWithCache>(of images: [MachO]) -> Set<String> {
        Set(images.map { DependencyLoadName.bareImageName(of: $0.imagePath) })
    }

    private func directBareImageNames<MachO: MachORepresentableWithCache>(of root: MachO) -> Set<String> {
        Set(root.dependencies.map { DependencyLoadName.bareImageName(of: $0.dylib.name) })
    }

    /// Regression: the image initializer used to hand each raw load path to
    /// `MachOImage(name:)`, which compares bare names, so it resolved nothing
    /// for its whole life. Nothing in-tree called it, which is how it survived.
    @MainActor
    @Test func imageInitializerResolvesTheMappedDirectDependencies() {
        let root = machOImage
        let dependencies = SwiftInterfaceBuilderDependencies(machO: root)
        let resolved = bareImageNames(of: dependencies.dependencies)
        #expect(resolved.contains("libswiftCore"))
        #expect(resolved.contains("Foundation"))
        #expect(resolved.isSubset(of: directBareImageNames(of: root)), "direct dependencies only")
    }

    @MainActor
    @Test func fileInitializerKeepsDirectSemanticsAndReportsMisses() {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let root = machOFile
        let dependencies = SwiftInterfaceBuilderDependencies(machO: root, searchPaths: [.systemDyldSharedCache])
        let resolved = bareImageNames(of: dependencies.dependencies)
        #expect(resolved.contains("libswiftCore"))
        #expect(resolved.isSubset(of: directBareImageNames(of: root)), "the cache-backed initializer never walks a dependency's own load commands")
        #expect(dependencies.unresolvedLoadNames.contains("@rpath/SymbolTestsHelper.framework/Versions/A/SymbolTestsHelper"), "the @rpath sibling is not in the cache and must be named, not dropped")
    }

    /// A host that resolved a transitive closure once can hand it over
    /// unchanged — the wrapper imposes no traversal of its own.
    @MainActor
    @Test func closureInitializerPreservesTheCallersTraversal() {
        guard FullDyldCache.host != nil else {
            print("skipped: no host dyld shared cache")
            return
        }
        let root = machOFile
        let direct = SwiftInterfaceBuilderDependencies(machO: root, searchPaths: [.systemDyldSharedCache])
        let transitive = SwiftInterfaceBuilderDependencies(closure: DependencyClosure(root: root, searchPaths: [.systemDyldSharedCache], traversal: .transitive))
        #expect(transitive.dependencies.count > direct.dependencies.count)
        #expect(transitive.machO.imagePath == root.imagePath)
    }
}
