import Foundation
import FoundationToolbox
import BinaryCodable
import APINotes

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
    let path: String
    let moduleName: String
    let apiNotesModule: APINotes.Module

    init(path: String) throws {
        self.path = path
        let apiNotesModule = try APINotes.Module(contentsOf: .init(filePath: path))
        self.moduleName = apiNotesModule.name
        self.apiNotesModule = apiNotesModule
    }
}

extension APINotes.Module: @unchecked @retroactive Sendable {}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
final class SDKIndexer: Sendable {
    let platform: SDKPlatform

    struct IndexOptions: OptionSet {
        let rawValue: Int

        static let indexSwiftModules = IndexOptions(rawValue: 1 << 0)
        static let indexAPINotesFiles = IndexOptions(rawValue: 1 << 1)
    }

    @Mutex
    var cacheIndexes: Bool = false

    @Mutex
    private(set) var modules: [SwiftModule] = []

    @Mutex
    private(set) var apiNotesFiles: [APINotesFile] = []

    @Mutex
    private(set) var searchPaths: [String] = [
        "usr/include",
        "usr/lib/swift",
        "System/Library/Frameworks",
        "System/Library/PrivateFrameworks",
    ]

    private let indexOptions: IndexOptions

    init(platform: SDKPlatform, options: IndexOptions = [.indexSwiftModules, .indexAPINotesFiles]) {
        self.platform = platform
        self.indexOptions = options
    }

    private var cacheURL: URL {
        .applicationSupportDirectory.appending(component: "MachOSwiftSection").appending(component: "SDKIndexer").appending(component: platform.rawValue)
    }

    nonisolated func index() async throws {
        var hasModulesCache = false
        if cacheURL.appending(component: "indexComplete").isExisted, indexOptions.contains(.indexSwiftModules) {
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
                if element.hasSuffix(".swiftmodule") {
                    let moduleName = element.lastPathComponent.deletingPathExtension
                    moduleFetchers.append { try await SwiftModule(moduleName: moduleName, path: fullPath, platform: platform) }
                } else if element.hasSuffix(".apinotes") {
                    let apinodesFile = try APINotesFile(path: fullPath)
                    apinotesFiles.append(apinodesFile)
                }
            }
        }
        if !hasModulesCache, indexOptions.contains(.indexSwiftModules) {
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
