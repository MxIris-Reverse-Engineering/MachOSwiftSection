import Foundation
import Dependencies

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
struct SwiftModule: Sendable, Codable {
    let moduleName: String
    let path: String
    let interfaceFile: SwiftInterfaceGeneratedFile
    let subModuleInterfaceFiles: [SwiftInterfaceGeneratedFile]

    init(moduleName: String, path: String, platform: SDKPlatform) async throws {
        @Dependency(\.sourceKitManager)
        var sourceKitManager
        
        self.moduleName = moduleName
        self.path = path
        let interfaceFile = try await sourceKitManager.interface(for: moduleName, in: platform)
        let indexer = SwiftInterfaceParser(file: interfaceFile)
        try await indexer.index()
        self.interfaceFile = interfaceFile

        let subModuleNames = await indexer.subModuleNames
        var subModuleInterfaceFiles: [SwiftInterfaceGeneratedFile] = []
        for subModuleName in subModuleNames {
            if let interfaceFile = try? await sourceKitManager.interface(for: subModuleName, in: platform) {
                subModuleInterfaceFiles.append(interfaceFile)
            }
        }
        self.subModuleInterfaceFiles = subModuleInterfaceFiles
    }

    @concurrent
    func write(toDirectory directoryPath: String) async throws {
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
