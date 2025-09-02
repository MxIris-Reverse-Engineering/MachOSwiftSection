import Foundation
import FoundationToolbox

struct TypeRecord: Sendable {
    let name: String
    let moduleName: String
}

final class TypeDatabase: Sendable {
    static let shared = TypeDatabase()

    @Mutex
    private var types: [String: TypeRecord] = [:]

    func index(_ filter: (SwiftModule) -> Bool) async throws {
        let indexer = SDKIndexer(platform: .macOS)
        indexer.cacheIndexes = true
        try await indexer.index()
        let modules = indexer.modules.filter(filter)
        let typeInfos = try await withThrowingTaskGroup { group in
            for module in modules {
                group.addTask {
                    var typeInfos: [SwiftInterfaceIndexer.TypeInfo] = []
                    let moduleIndexer = module.indexer()
                    try await moduleIndexer.interfaceIndexer.index()
                    typeInfos.append(contentsOf: moduleIndexer.interfaceIndexer.typeInfos)
                    let subModuleTypeInfos = try await withThrowingTaskGroup { innerGroup in
                        for subModuleInterfaceIndexer in moduleIndexer.subModuleInterfaceIndexers {
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
                    typeInfos.append(contentsOf: subModuleTypeInfos)
                    return (module.moduleName, typeInfos)
                }
            }
            var results: [(moduleName: String, typeInfos: [SwiftInterfaceIndexer.TypeInfo])] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        var types: [String: TypeRecord] = [:]
        for (moduleName, typeInfos) in typeInfos {
            for typeInfo in typeInfos {
                types[typeInfo.name] = .init(name: typeInfo.name, moduleName: moduleName)
            }
        }
        self.types = types
    }

    func moduleName(forTypeName typeName: String) -> String? {
        types[typeName]?.moduleName
    }
}
