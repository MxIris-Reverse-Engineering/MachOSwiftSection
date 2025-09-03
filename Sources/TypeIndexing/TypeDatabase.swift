import Foundation
import FoundationToolbox
import APINotes

struct TypeRecord: Sendable {
    let name: String
    let moduleName: String
}

package final class TypeDatabase: Sendable {
    package static let shared = TypeDatabase()

    @Mutex
    private var types: [String: TypeRecord] = [:]

    package func index(_ filter: (_ moduleName: String) -> Bool) async throws {
        let indexer = SDKIndexer(platform: .macOS)
        indexer.cacheIndexes = true
        try await indexer.index()
        let modules = indexer.modules.filter { filter($0.moduleName) }
        let typeInfos = try await typeInfo(of: modules)

        var types: [String: TypeRecord] = [:]
        for (moduleName, typeInfos) in typeInfos {
            for typeInfo in typeInfos {
                types[typeInfo.name] = .init(name: typeInfo.name, moduleName: moduleName)
            }
        }
        self.types = types
    }

    private typealias TypeInfoResults = (moduleName: String, typeInfos: [SwiftInterfaceIndexer.TypeInfo])

    private func typeInfo(of modules: [SwiftModule]) async throws -> [TypeInfoResults] {
        try await withThrowingTaskGroup { group in
            for module in modules {
                group.addTask {
                    var typeInfos: [SwiftInterfaceIndexer.TypeInfo] = []
                    let moduleIndexer = module.indexer()
                    try await moduleIndexer.interfaceIndexer.index()
                    typeInfos.append(contentsOf: moduleIndexer.interfaceIndexer.typeInfos)
                    try await typeInfos.append(contentsOf: self.subModuleTypeInfos(of: moduleIndexer))
                    return (module.moduleName, typeInfos)
                }
            }
            var results: [TypeInfoResults] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func subModuleTypeInfos(of indexer: SwiftModuleIndexer) async throws -> [SwiftInterfaceIndexer.TypeInfo] {
        try await withThrowingTaskGroup { innerGroup in
            for subModuleInterfaceIndexer in indexer.subModuleInterfaceIndexers {
                innerGroup.addTask {
                    var typeInfos: [SwiftInterfaceIndexer.TypeInfo] = []
                    try await subModuleInterfaceIndexer.index()
                    typeInfos.append(contentsOf: subModuleInterfaceIndexer.typeInfos)
                    return typeInfos
                }
            }
            var subModuleTypeInfos: [[SwiftInterfaceIndexer.TypeInfo]] = []
            for try await result in innerGroup {
                subModuleTypeInfos.append(result)
            }
            return subModuleTypeInfos.flatMap { $0 }
        }
    }

    package func moduleName(forTypeName typeName: String) -> String? {
        types[typeName]?.moduleName
    }
}
