#if os(macOS)

import Foundation
import FoundationToolbox
import BinaryCodable
import APINotes
import os

@available(macOS 13.0, *)
struct SwiftModuleIndexer {
    let moduleName: String
    let path: String
    let interfaceIndexer: SwiftInterfaceParser
    let subModuleInterfaceIndexers: [SwiftInterfaceParser]

    private static let logger = Logger(subsystem: "com.MxIris.MachOSwiftSection.TypeIndexing", category: "SwiftModuleIndexer")

    init(module: SwiftModule) {
        Self.logger.debug("Initializing SwiftModuleIndexer for module: \(module.moduleName) at path: \(module.path)")

        self.moduleName = module.moduleName
        self.path = module.path

        Self.logger.debug("Creating interface indexer for module: \(module.moduleName)")
        let interfaceIndexer = SwiftInterfaceParser(file: module.interfaceFile)
        self.interfaceIndexer = interfaceIndexer

        var subModuleInterfaceIndexers: [SwiftInterfaceParser] = []
        Self.logger.debug("Processing \(module.subModuleInterfaceFiles.count) sub-module interface files for module: \(module.moduleName)")

        for subModuleInterfaceFile in module.subModuleInterfaceFiles {
            Self.logger.debug("Creating sub-module interface indexer for module: \(subModuleInterfaceFile.moduleName)")
            let subModuleInterfaceIndexer = SwiftInterfaceParser(file: subModuleInterfaceFile)
            subModuleInterfaceIndexers.append(subModuleInterfaceIndexer)
        }
        self.subModuleInterfaceIndexers = subModuleInterfaceIndexers

        Self.logger.info("Successfully initialized SwiftModuleIndexer for module: \(module.moduleName) with \(subModuleInterfaceIndexers.count) sub-modules")
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
@available(macOS 13.0, *)
struct APINotesFile: Sendable, Codable {
    let path: String
    let moduleName: String
    let apiNotesModule: APINotes.Module

    private static let logger = Logger(subsystem: "com.MxIris.MachOSwiftSection.TypeIndexing", category: "APINotesFile")

    init(path: String) throws {
        Self.logger.debug("Initializing APINotesFile from path: \(path)")

        self.path = path

        do {
            let apiNotesModule = try APINotes.Module(contentsOf: .init(filePath: path))
            self.moduleName = apiNotesModule.name
            self.apiNotesModule = apiNotesModule

            Self.logger.info("Successfully loaded API Notes module: \(apiNotesModule.name) from path: \(path)")
        } catch {
            Self.logger.error("Failed to load API Notes from path: \(path), error: \(error.localizedDescription)")
            throw error
        }
    }
}

extension APINotes.Module: @unchecked @retroactive Sendable {}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
@available(macOS 13.0, *)
final class SDKIndexer: Sendable {
    struct IndexOptions: OptionSet {
        let rawValue: Int

        static let indexSwiftModules = IndexOptions(rawValue: 1 << 0)
        static let indexAPINotesFiles = IndexOptions(rawValue: 1 << 1)
    }

    private static let logger = Logger(subsystem: "com.MxIris.MachOSwiftSection.TypeIndexing", category: "SDKIndexer")

    let platform: SDKPlatform

    let indexOptions: IndexOptions

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

    init(platform: SDKPlatform, options: IndexOptions = [.indexSwiftModules, .indexAPINotesFiles]) {
        Self.logger.info("Initializing SDKIndexer for platform: \(platform.rawValue) with options: \(options.rawValue)")
        self.platform = platform
        self.indexOptions = options
        let searchPaths = self.searchPaths
        Self.logger.debug("SDKIndexer initialized with search paths: \(searchPaths)")
    }

    private var cacheURL: URL {
        let url = URL.applicationSupportDirectory.appending(component: "MachOSwiftSection").appending(component: "SDKIndexer").appending(component: platform.rawValue)
        Self.logger.debug("Cache URL: \(url.path)")
        return url
    }

    @concurrent
    func index() async throws {
        Self.logger.info("Starting SDK indexing for platform: \(self.platform.rawValue)")
        let startTime = CFAbsoluteTimeGetCurrent()

        var hasModulesCache = false
        let cacheCompleteURL = cacheURL.appending(component: "indexComplete")

        if cacheCompleteURL.isExisted, indexOptions.contains(.indexSwiftModules) {
            Self.logger.info("Found existing cache, loading cached modules from: \(cacheURL.path)")

            do {
                var modules: [SwiftModule] = []
                let indexDatas = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)

                Self.logger.debug("Found \(indexDatas.count) files in cache directory")

                for indexData in indexDatas {
                    guard indexData.path().hasSuffix(".index") else {
                        continue
                    }

                    Self.logger.debug("Loading cached module from: \(indexData.lastPathComponent)")
                    let data = try Data(contentsOf: indexData)
                    let module = try BinaryDecoder().decode(SwiftModule.self, from: data)
                    modules.append(module)
                }

                self.modules = modules.sorted { $0.moduleName < $1.moduleName }
                hasModulesCache = true
                Self.logger.info("Successfully loaded \(modules.count) modules from cache")

            } catch {
                Self.logger.error("Failed to load modules from cache: \(error.localizedDescription)")
                hasModulesCache = false
            }
        } else {
            Self.logger.info("No cache found or cache indexing disabled")
        }

        var moduleFetchers: [() async throws -> SwiftModule] = []
        var apinotesFiles: [APINotesFile] = []
        let platform = self.platform
        let sdkRoot = platform.sdkPath

        Self.logger.info("Starting file system scan with SDK root: \(sdkRoot)")

        for searchPath in searchPaths {
            let fullSearchPath = sdkRoot.box.appendingPathComponent(searchPath)
            Self.logger.debug("Scanning search path: \(fullSearchPath)")

            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: fullSearchPath) else {
                Self.logger.debug("Search path does not exist: \(fullSearchPath)")
                continue
            }

            let enumerator = fileManager.enumerator(atPath: fullSearchPath)
            var swiftModuleCount = 0
            var apiNotesCount = 0

            while let element = enumerator?.nextObject() as? String {
                let fullPath = fullSearchPath.box.appendingPathComponent(element)

                if element.hasSuffix(".swiftmodule") {
                    let moduleName = element.lastPathComponent.deletingPathExtension
                    Self.logger.debug("Found Swift module: \(moduleName) at path: \(fullPath)")
                    moduleFetchers.append { try await SwiftModule(moduleName: moduleName, path: fullPath, platform: platform) }
                    swiftModuleCount += 1
                } else if element.hasSuffix(".apinotes") {
                    Self.logger.debug("Found API Notes file: \(element) at path: \(fullPath)")
                    do {
                        let apinodesFile = try APINotesFile(path: fullPath)
                        apinotesFiles.append(apinodesFile)
                        apiNotesCount += 1
                    } catch {
                        Self.logger.error("Failed to load API Notes file at \(fullPath): \(error.localizedDescription)")
                    }
                }
            }

            Self.logger.info("Completed scanning \(searchPath): found \(swiftModuleCount) Swift modules and \(apiNotesCount) API Notes files")
        }

        if !hasModulesCache, indexOptions.contains(.indexSwiftModules) {
            Self.logger.info("Loading \(moduleFetchers.count) Swift modules from file system")

            var modules: [SwiftModule] = []
            var successCount = 0
            var failureCount = 0

            for (index, moduleFetcher) in moduleFetchers.enumerated() {
                do {
                    let module = try await moduleFetcher()
                    modules.append(module)
                    successCount += 1
                    Self.logger.debug("Successfully loaded module \(index + 1)/\(moduleFetchers.count): \(module.moduleName)")
                } catch {
                    failureCount += 1
                    Self.logger.error("Failed to load module \(index + 1)/\(moduleFetchers.count): \(error.localizedDescription)")
                }
            }

            self.modules = modules.sorted { $0.moduleName < $1.moduleName }
            Self.logger.info("Module loading completed: \(successCount) successful, \(failureCount) failed")

            if cacheIndexes {
                Self.logger.info("Caching \(modules.count) modules to disk")

                do {
                    let directoryURL = cacheURL
                    try directoryURL.createDirectoryIfNeeded()

                    for module in modules {
                        Self.logger.debug("Caching module: \(module.moduleName)")
                        let data = try BinaryEncoder().encode(module)
                        try data.write(to: directoryURL.appending(component: "\(module.moduleName).index"))
                    }

                    try "".write(to: directoryURL.appending(component: "indexComplete"), atomically: true, encoding: .utf8)
                    Self.logger.info("Successfully cached all modules")

                } catch {
                    Self.logger.error("Failed to cache modules: \(error.localizedDescription)")
                }
            }
        }

        apiNotesFiles = apinotesFiles

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime

        Self.logger.info("SDK indexing completed in \(String(format: "%.2f", duration)) seconds")
        Self.logger.info("Final results: \(modules.count) Swift modules, \(apinotesFiles.count) API Notes files")
    }
}

@available(macOS 13.0, *)
extension URL {
    var isExisted: Bool {
        let exists = FileManager.default.fileExists(atPath: path(percentEncoded: false))
        Logger(subsystem: "com.sdkindexer", category: "URL").debug("Checking existence of path: \(path) - exists: \(exists)")
        return exists
    }

    func createDirectoryIfNeeded() throws {
        let logger = Logger(subsystem: "com.sdkindexer", category: "URL")
        let fileManager = FileManager.default
        let pathString = path(percentEncoded: false)

        if !fileManager.fileExists(atPath: pathString) {
            logger.info("Creating directory: \(pathString)")
            do {
                try fileManager.createDirectory(at: self, withIntermediateDirectories: true)
                logger.info("Successfully created directory: \(pathString)")
            } catch {
                logger.error("Failed to create directory: \(pathString), error: \(error.localizedDescription)")
                throw error
            }
        } else {
            logger.debug("Directory already exists: \(pathString)")
        }
    }
}

#endif
