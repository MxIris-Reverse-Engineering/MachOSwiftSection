import Foundation
import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
@preconcurrency import MachOKit
import MachODependencies
import MachOSwiftSection

/// The images a provider such as TypeIndexing's
/// `SwiftInterfaceBuilderTypeNameProvider` works against: the root plus its
/// **direct** dependencies only.
///
/// Direct on purpose. TypeIndexing generates a SourceKit module interface per
/// dependency module, so its cost is linear in this list; the transitive
/// closure of an OS framework runs to hundreds of images and would bring back
/// the whole-SDK generation that once made that target unusable (evolution
/// proposal 0009). A caller that genuinely wants the transitive set builds a
/// `DependencyClosure` with `.transitive` and hands it to `init(closure:)`.
@dynamicMemberLookup
public struct SwiftInterfaceBuilderDependencies<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: Sendable {
    public let machO: MachO

    public let dependencies: [MachO]

    /// Load names of the root's dependencies no locator could resolve — the
    /// exact complement of `dependencies`, so a host can say *which* images
    /// its attribution will miss instead of guessing from an empty list.
    public let unresolvedLoadNames: [String]

    public subscript<Value>(dynamicMember keyPath: KeyPath<Self, Value>) -> Value {
        self[keyPath: keyPath]
    }

    /// Wraps an already-resolved closure — any traversal, any locator — so a
    /// host that resolved dependencies once can share them with every consumer.
    public init(closure: DependencyClosure<MachO>) {
        self.machO = closure.root
        self.dependencies = closure.images
        self.unresolvedLoadNames = closure.unresolvedLoadNames
    }
}

extension SwiftInterfaceBuilderDependencies<MachOFile> {
    /// Resolves the root's direct dependencies through `searchPaths`
    /// (`FileDependencyLocator`: exact install path first, ranked bare-name
    /// match second).
    ///
    /// - Parameter eventHandlers: Sinks for the search paths that fail to
    ///   open. Defaulted, so existing call sites are unaffected — and passing
    ///   none is safe rather than silent: `SwiftIndexEvents.Dispatcher` reports
    ///   an unhandled failure to os_log rather than dropping it.
    public init(machO: MachO, searchPaths: [DependencySearchPath], eventHandlers: [SwiftIndexEvents.Handler] = []) {
        let closure = DependencyClosure(root: machO, searchPaths: searchPaths, traversal: .direct)
        if !closure.searchPathLoadFailures.isEmpty {
            let eventDispatcher = SwiftIndexEvents.Dispatcher()
            eventDispatcher.addHandlers(eventHandlers)
            for loadFailure in closure.searchPathLoadFailures {
                eventDispatcher.dispatch(
                    .renderingDegraded(
                        context: .init(source: .dependencyLoad, subject: Self.eventSubject(for: loadFailure.searchPath)),
                        error: loadFailure.error
                    )
                )
            }
        }
        self.init(closure: closure)
    }

    @available(*, deprecated, renamed: "init(machO:searchPaths:eventHandlers:)")
    public init(machO: MachO, paths: [DependencyPath], eventHandlers: [SwiftIndexEvents.Handler] = []) {
        self.init(machO: machO, searchPaths: paths.map(\.searchPath), eventHandlers: eventHandlers)
    }

    /// The event subject stays the bare path for file and cache entries, as it
    /// was before the search paths were unified.
    private static func eventSubject(for searchPath: DependencySearchPath) -> String {
        switch searchPath {
        case .machOFile(let path), .dyldSharedCache(let path):
            return path
        case .systemDyldSharedCache:
            return searchPath.description
        }
    }
}

extension SwiftInterfaceBuilderDependencies<MachOImage> {
    /// Resolves the root's direct dependencies through the active dyld
    /// (`InProcessDependencyLocator`, which normalizes each load name to the
    /// bare image name `MachOImage(name:)` matches on — handing it the raw
    /// load path resolved nothing).
    public init(machO: MachO) {
        self.init(closure: DependencyClosure(root: machO, traversal: .direct))
    }
}
