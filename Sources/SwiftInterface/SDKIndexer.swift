import Foundation
import FoundationToolbox
import BinaryCodable

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
struct SwiftModule: Sendable, Codable {
    let moduleName: String
    let path: String
    let interfaceFile: SwiftInterfaceGeneratedFile
    let subModuleInterfaceFiles: [SwiftInterfaceGeneratedFile]

    init(moduleName: String, path: String, platform: SKPlatform) async throws {
        self.moduleName = moduleName
        self.path = path
        let interfaceFile = try await SourceKitManager.shared.interface(for: moduleName, in: platform)
        let indexer = SwiftInterfaceIndexer(file: interfaceFile)
        try await indexer.index()
        self.interfaceFile = interfaceFile

        let subModuleNames = indexer.subModuleNames
        var subModuleInterfaceFiles: [SwiftInterfaceGeneratedFile] = []
        for subModuleName in subModuleNames {
            if let interfaceFile = try? await SourceKitManager.shared.interface(for: subModuleName, in: platform) {
                subModuleInterfaceFiles.append(interfaceFile)
            }
        }
        self.subModuleInterfaceFiles = subModuleInterfaceFiles
    }

    nonisolated func write(toDirectory directoryPath: String) async throws {
        var directoryURL = URL(filePath: directoryPath)
        directoryURL.append(component: moduleName)
        if !FileManager.default.fileExists(atPath: directoryURL.path()) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        var moduleDirectoryURL = directoryURL
        moduleDirectoryURL.append(component: "\(moduleName).swiftinterface")
        try interfaceFile.contents.write(to: directoryURL, atomically: true, encoding: .utf8)
        for subModuleInterfaceFile in subModuleInterfaceFiles {
            var subModuleDirectoryURL = directoryURL
            subModuleDirectoryURL.append(component: "\(subModuleInterfaceFile.moduleName).swiftinterface")
            try subModuleInterfaceFile.contents.write(to: subModuleDirectoryURL, atomically: true, encoding: .utf8)
        }
    }

    func indexer() -> SwiftModuleIndexer {
        SwiftModuleIndexer(module: self)
    }
}

struct SwiftModuleIndexer {
    let moduleName: String
    let path: String
    let interfaceIndexer: SwiftInterfaceIndexer
    let subModuleInterfaceIndexers: [SwiftInterfaceIndexer]

    init(module: borrowing SwiftModule) {
        self.moduleName = module.moduleName
        self.path = module.path
        let interfaceIndexer = SwiftInterfaceIndexer(file: module.interfaceFile)
        self.interfaceIndexer = interfaceIndexer
        var subModuleInterfaceIndexers: [SwiftInterfaceIndexer] = []
        for subModuleInterfaceFile in module.subModuleInterfaceFiles {
            let subModuleInterfaceIndexer = SwiftInterfaceIndexer(file: subModuleInterfaceFile)
            subModuleInterfaceIndexers.append(subModuleInterfaceIndexer)
        }
        self.subModuleInterfaceIndexers = subModuleInterfaceIndexers
    }
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
struct SwiftInterfaceFile: Sendable, Codable {
    let moduleName: String
    let path: String
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
struct SwiftInterfaceGeneratedFile: Sendable, Codable {
    let moduleName: String
    let contents: String
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
struct APINotesFile: Sendable, Codable {
    let moduleName: String
    let path: String
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
final class SDKIndexer: Sendable {
    let platform: SKPlatform

    @Mutex
    var cacheIndexes: Bool = false

    @Mutex
    private(set) var modules: [SwiftModule] = []

    @Mutex
    private(set) var apiNotesFiles: [APINotesFile] = []

    @Mutex
    private(set) var searchPaths: [String] = [
        "usr/lib/swift",
        "System/Library/Frameworks",
        "System/Library/PrivateFrameworks",
    ]

    init(platform: SKPlatform) {
        self.platform = platform
    }

    private var cacheURL: URL {
        .applicationSupportDirectory.appending(component: "MachOSwiftSection").appending(component: "SDKIndexer").appending(component: platform.rawValue)
    }

    nonisolated func index() async throws {
        var hasModulesCache = false
        if cacheURL.appending(component: "indexComplete").isExisted {
            var modules: [SwiftModule] = []
            let indexDatas = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
            for indexData in indexDatas {
                guard indexData.path().hasSuffix(".index") else {
                    continue
                }
                let data = try Data(contentsOf: indexData)
                let module = try BinaryDecoder().decode(SwiftModule.self, from: data)
                modules.append(module)
            }
            self.modules = modules.sorted { $0.moduleName < $1.moduleName }
            hasModulesCache = true
        }
        var moduleFetchers: [() async throws -> SwiftModule] = []
        var apinotesFiles: [APINotesFile] = []
        let platform = platform
        let sdkRoot = platform.sdkPath
        for searchPath in searchPaths {
            let fullSearchPath = sdkRoot.box.appendingPathComponent(searchPath)
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: fullSearchPath) else {
                continue
            }
            let enumerator = fileManager.enumerator(atPath: fullSearchPath)
            while let element = enumerator?.nextObject() as? String {
                let fullPath = fullSearchPath.box.appendingPathComponent(element)
                let moduleName = element.lastPathComponent.deletingPathExtension
                if element.hasSuffix(".swiftmodule") {
                    moduleFetchers.append { try await SwiftModule(moduleName: moduleName, path: fullPath, platform: platform) }
                } else if element.hasSuffix(".apinotes") {
                    let apinodesFile = APINotesFile(moduleName: moduleName, path: fullPath)
                    apinotesFiles.append(apinodesFile)
                }
            }
        }
        if !hasModulesCache {
            var modules: [SwiftModule] = []
            for moduleFetcher in moduleFetchers {
                if let module = try? await moduleFetcher() {
                    modules.append(module)
                }
            }
            self.modules = modules.sorted { $0.moduleName < $1.moduleName }
            if cacheIndexes {
                let directoryURL = cacheURL
                try directoryURL.createDirectoryIfNeeded()
                for module in modules {
                    let data = try BinaryEncoder().encode(module)
                    try data.write(to: directoryURL.appending(component: "\(module.moduleName).index"))
                }
                try "".write(to: directoryURL.appending(component: "indexComplete"), atomically: true, encoding: .utf8)
            }
        }

        apiNotesFiles = apinotesFiles
    }
}

extension URL {
    var isExisted: Bool {
        FileManager.default.fileExists(atPath: path(percentEncoded: false))
    }

    func createDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path(percentEncoded: false)) {
            try fileManager.createDirectory(at: self, withIntermediateDirectories: true)
        }
    }
}
