import Foundation
import Testing
@testable import SwiftInterface
import Sylvester

final class SDKIndexerTests {
    @Test func index() async throws {
        let indexer = SDKIndexer(sdkRoot: SKPlatform.macOS.sdkPath)
        let contentDirectory = URL.desktopDirectory.appendingPathComponent("SylvesterInterfaces")
        if !FileManager.default.fileExists(atPath: contentDirectory.path) {
            try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        }
        try await indexer.index()
        var results: [String: [SwiftInterfaceFile]] = [:]
        for module in indexer.modules {
            await Task {
                do {
                    let moduleContentDirectory = contentDirectory.appendingPathComponent(module.moduleName)
                    if !FileManager.default.fileExists(atPath: moduleContentDirectory.path) {
                        try FileManager.default.createDirectory(at: moduleContentDirectory, withIntermediateDirectories: true)
                    }
                    let response = try await SylvesterInterface.shared.sendAsync(SKEditorOpenInterfaceRequest(moduleName: module.moduleName))
                    let url = moduleContentDirectory.appendingPathComponent("\(module.moduleName).swiftinterface")
                    try response.sourceText.write(to: url, atomically: true, encoding: .utf8)
                    let generatedFile = SwiftInterfaceGeneratedFile(moduleName: module.moduleName, contents: response.sourceText)
                    let file = SwiftInterfaceFile(moduleName: module.moduleName, path: url.path)
                    results[module.moduleName, default: []].append(file)
                    let indexer = SwiftInterfaceIndexer(file: generatedFile)
                    try await indexer.index()
                    for subModuleName in indexer.subModuleNames {
                        try await Task {
                            let response = try await SylvesterInterface.shared.sendAsync(SKEditorOpenInterfaceRequest(moduleName: subModuleName))
                            let url = moduleContentDirectory.appendingPathComponent("\(subModuleName).swiftinterface")
                            try response.sourceText.write(to: url, atomically: true, encoding: .utf8)
                            let file = SwiftInterfaceFile(moduleName: subModuleName, path: url.path)
                            results[module.moduleName, default: []].append(file)
                        }.value
                    }
                } catch {
                    print("[Module]", module.moduleName)
                    print("[Error]", error)
                }
            }.value
        }
        for (moduleName, files) in results {
            print("[Module]", moduleName, files.count)
            for file in files where file.moduleName != moduleName {
                print(" -", file.moduleName)
            }
        }
    }
}
