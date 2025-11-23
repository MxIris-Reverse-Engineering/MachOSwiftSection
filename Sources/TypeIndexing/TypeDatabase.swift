#if os(macOS)

import Foundation
import FoundationToolbox
import APINotes
import MachOKit

@available(macOS 13.0, *)
package final class TypeDatabase<MachO: MachORepresentable & Sendable>: Sendable {
    package struct Record: Sendable {
        package let moduleName: String
        package let typeName: String
    }

    private let apiNotesManager: APINotesManager

    private let sdkIndexer: SDKIndexer

    private let objcInterfaceIndexer: ObjCInterfaceIndexer<MachO>

    @Mutex
    private var types: [String: Record] = [:]

    package init(platform: SDKPlatform) {
        self.apiNotesManager = .init()
        self.sdkIndexer = .init(platform: platform)
        self.objcInterfaceIndexer = .init()
        sdkIndexer.cacheIndexes = true
    }

    package func index(dependencies: [MachO], filter: (String) -> Bool) async throws {
        try await sdkIndexer.index()

        let modules = sdkIndexer.modules.filter { filter($0.moduleName) }

        let typeInfos = try await typeInfo(of: modules)

        var types: [String: Record] = [:]

        for (moduleName, typeInfos) in typeInfos {
            for typeInfo in typeInfos {
                types[typeInfo.name] = .init(moduleName: moduleName, typeName: typeInfo.name)
            }
        }

        apiNotesManager.addFiles(sdkIndexer.apiNotesFiles)
        apiNotesManager.index()

        for (_, cName) in apiNotesManager.swiftNameToCName {
            types[cName.name] = .init(moduleName: cName.moduleName, typeName: cName.name)
        }

//        for dependency in dependencies {
//            try objcInterfaceIndexer.index(in: dependency)
//        }
//
//        for (image, classInfos) in objcInterfaceIndexer.classInfos {
//            for classInfo in classInfos {
//                print(image, classInfo.name)
//            }
//        }
//
//        for (image, protocolInfos) in objcInterfaceIndexer.protocolInfos {
//            for protocolInfo in protocolInfos {
//                print(image, protocolInfo.name)
//            }
//        }

        self.types = types
    }

    package func moduleName(forTypeName typeName: String) -> String? {
        types[typeName]?.moduleName
    }

    package func swiftName(forCName cName: String) -> String? {
        apiNotesManager.swiftName(forCName: cName)?.name
    }

    private typealias TypeInfoResults = (moduleName: String, typeInfos: [SwiftInterfaceParser.TypeInfo])

    private func typeInfo(of modules: [SwiftModule]) async throws -> [TypeInfoResults] {
        try await withThrowingTaskGroup { group in
            for module in modules {
                group.addTask {
                    var typeInfos: [SwiftInterfaceParser.TypeInfo] = []
                    let moduleIndexer = module.indexer()
                    try await moduleIndexer.interfaceIndexer.index()
                    await typeInfos.append(contentsOf: moduleIndexer.interfaceIndexer.typeInfos)
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

    private func subModuleTypeInfos(of indexer: SwiftModuleIndexer) async throws -> [SwiftInterfaceParser.TypeInfo] {
        try await withThrowingTaskGroup { innerGroup in
            for subModuleInterfaceIndexer in indexer.subModuleInterfaceIndexers {
                innerGroup.addTask {
                    var typeInfos: [SwiftInterfaceParser.TypeInfo] = []
                    try await subModuleInterfaceIndexer.index()
                    await typeInfos.append(contentsOf: subModuleInterfaceIndexer.typeInfos)
                    return typeInfos
                }
            }
            var subModuleTypeInfos: [[SwiftInterfaceParser.TypeInfo]] = []
            for try await result in innerGroup {
                subModuleTypeInfos.append(result)
            }
            return subModuleTypeInfos.flatMap { $0 }
        }
    }
}


#endif
