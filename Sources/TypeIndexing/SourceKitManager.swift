import Foundation
import SourceKitD
import FoundationToolbox
import Dependencies

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
final class SourceKitManager: Sendable {
    fileprivate static let shared = SourceKitManager()

    @Mutex
    private var _sourcekitd: SourceKitD? = nil

    private var sourcekitd: SourceKitD {
        get async throws {
            if let _sourcekitd {
                return _sourcekitd
            } else {
                let sourcekitd = try await SourceKitD.getOrCreate(dylibPath: .init(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd"), pluginPaths: nil)
                _sourcekitd = sourcekitd
                return sourcekitd
            }
        }
    }

    func interface(for moduleName: String, in platform: SDKPlatform) async throws -> SwiftInterfaceGeneratedFile {
        let keys = try await sourcekitd.keys
        let request = try await sourcekitd.dictionary([
            keys.moduleName: moduleName,
            keys.name: UUID().uuidString,
            keys.compilerArgs: ["-sdk", platform.sdkPath],
        ])
        let response = try await sourcekitd.send(\.editorOpenInterface, request, timeout: .seconds(60), restartTimeout: .seconds(60), documentUrl: nil, fileContents: nil)
        guard let sourceText: String = response[keys.sourceText] else {
            throw NSError(domain: "SourceKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No source text in response"])
        }
        return .init(moduleName: moduleName, contents: sourceText)
    }
}

private enum SourceKitManagerKey: DependencyKey {
    static let liveValue: SourceKitManager = .shared
    static let testValue: SourceKitManager = .shared
}

extension DependencyValues {
    var sourceKitManager: SourceKitManager {
        get { self[SourceKitManagerKey.self] }
        set { self[SourceKitManagerKey.self] = newValue }
    }
}
