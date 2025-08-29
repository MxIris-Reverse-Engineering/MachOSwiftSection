import Foundation
import FoundationToolbox

struct SwiftModule: Sendable {
    let moduleName: String
    let path: String
    let interfaceFiles: [SwiftInterfaceFile]

    init(moduleName: String, path: String) throws {
        self.moduleName = moduleName
        self.path = path
        self.interfaceFiles = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".swiftinterface") }.map {
            SwiftInterfaceFile(moduleName: moduleName, path: path.box.appendingPathComponent($0))
        }
    }
}

struct SwiftInterfaceFile: Sendable {
    let moduleName: String
    let path: String
}

final class SDKIndexer: Sendable {
    let sdkRoot: String

    @Mutex
    var modules: [SwiftModule] = []

    @Mutex
    var searchPaths: [String] = [
        "usr/lib/swift",
        "System/Library/Frameworks",
        "System/Library/PrivateFrameworks",
    ]

    init(sdkRoot: String) {
        self.sdkRoot = sdkRoot
    }

    nonisolated func index() async throws {
        var modules: [SwiftModule] = []
        for searchPath in searchPaths {
            let fullSearchPath = sdkRoot.box.appendingPathComponent(searchPath)
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: fullSearchPath) else {
                continue
            }
            let enumerator = fileManager.enumerator(atPath: fullSearchPath)
            while let element = enumerator?.nextObject() as? String {
                guard element.hasSuffix(".swiftmodule") else {
                    continue
                }
                let fullPath = fullSearchPath.box.appendingPathComponent(element)
                let moduleName = element.lastPathComponent.deletingPathExtension
                try modules.append(SwiftModule(moduleName: moduleName, path: fullPath))
            }
        }
        self.modules = modules
    }
}
