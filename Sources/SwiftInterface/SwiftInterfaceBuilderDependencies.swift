import Foundation
import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
@preconcurrency import MachOKit
import MachOSwiftSection

@dynamicMemberLookup
public struct SwiftInterfaceBuilderDependencies<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: Sendable {
    public let machO: MachO

    public let dependencies: [MachO]

    public subscript<Value>(dynamicMember keyPath: KeyPath<Self, Value>) -> Value {
        self[keyPath: keyPath]
    }
}

extension SwiftInterfaceBuilderDependencies<MachOFile> {
    /// - Parameter eventHandlers: Sinks for the dependencies that fail to load.
    ///   Defaulted, so existing call sites are unaffected — and passing none is
    ///   safe rather than silent: `SwiftIndexEvents.Dispatcher` reports an
    ///   unhandled failure to os_log rather than dropping it.
    public init(machO: MachO, paths: [DependencyPath], eventHandlers: [SwiftIndexEvents.Handler] = []) {
        var dependencies: [MachOFile] = []
        let dependencyPaths = Set(machO.dependencies.map(\.dylib.name))
        let eventDispatcher = SwiftIndexEvents.Dispatcher()
        eventDispatcher.addHandlers(eventHandlers)

        for searchPath in paths {
            switch searchPath {
            case .machO(let path):
                do {
                    if let machOFile = try File.loadFromFile(url: .init(fileURLWithPath: path)).machOFiles.first {
                        dependencies.append(machOFile)
                    } else {}
                } catch {
                    eventDispatcher.dispatch(
                        .renderingDegraded(
                            context: .init(source: .dependencyLoad, subject: path),
                            error: error
                        )
                    )
                }
            case .dyldSharedCache(let path):
                do {
                    let fullDyldCache = try FullDyldCache(url: .init(fileURLWithPath: path))
                    var foundCount = 0
                    for machOFile in fullDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                        dependencies.append(machOFile)
                        foundCount += 1
                    }
                } catch {
                    eventDispatcher.dispatch(
                        .renderingDegraded(
                            context: .init(source: .dependencyLoad, subject: path),
                            error: error
                        )
                    )
                }
            case .usesSystemDyldSharedCache:
                if let hostDyldCache = FullDyldCache.host {
                    var foundCount = 0
                    for machOFile in hostDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                        dependencies.append(machOFile)
                        foundCount += 1
                    }
                }
            }
        }
        self.machO = machO
        self.dependencies = dependencies
    }
}

extension SwiftInterfaceBuilderDependencies<MachOImage> {
    public init(machO: MachO) {
        var dependencies: [MachO] = []
        let dependencyNames = machO.dependencies.map(\.dylib.name)

        for dependencyPath in dependencyNames {
            if let machO = MachOImage(name: dependencyPath) {
                dependencies.append(machO)
            }
        }

        self.machO = machO
        self.dependencies = dependencies
    }
}
