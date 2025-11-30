#if os(macOS)
import MachOKit
import MachOSwiftSection
import SwiftInterface

@available(macOS 13.0, *)
public final class SwiftInterfaceBuilderTypeNameProvider<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: SwiftInterfaceBuilderExtraDataProvider, Sendable {
    public let machO: MachO

    private let typeDatabase: TypeDatabase<MachO>

    private let dependencies: SwiftInterfaceBuilderDependencies<MachO>

    public init?(machO: MachO, dependencies: SwiftInterfaceBuilderDependencies<MachO>) {
        self.machO = machO
        self.dependencies = dependencies
        guard let platform = machO.loadCommands.buildVersionCommand?.platform.sdkPlatform else {
            return nil
        }
        self.typeDatabase = .init(platform: platform)
    }

    public func setup() async throws {
        let dependencyModules = Set(dependencies.dependencies.map(\.imagePath.lastPathComponent.deletingPathExtension.deletingPathExtension.strippedLibSwiftPrefix))
        try await typeDatabase.index(dependencies: dependencies.dependencies) { dependencyModules.contains($0) }
    }

    public func moduleName(forTypeName typeName: String) async -> String? {
        typeDatabase.moduleName(forTypeName: typeName)
    }

    public func swiftName(forCName cName: String) async -> String? {
        typeDatabase.swiftName(forCName: cName)
    }
}

@available(macOS 13.0, *)
extension MachOKit.Platform {
    var sdkPlatform: SDKPlatform? {
        switch self {
        case .macOS,
             .macCatalyst:
            return .macOS
        case .driverKit:
            return .driverKit
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        case .iOSSimulator:
            return .iOSSimulator
        case .tvOSSimulator:
            return .tvOSSimulator
        case .watchOSSimulator:
            return .watchOSSimulator
        case .visionOSSimulator:
            return .visionOSSimulator
        default:
            return nil
        }
    }
}

extension LoadCommandsProtocol {
    var buildVersionCommand: BuildVersionCommand? {
        for command in self {
            switch command {
            case .buildVersion(let buildVersionCommand):
                return buildVersionCommand
            default:
                break
            }
        }
        return nil
    }
}

extension String {
    var strippedLibSwiftPrefix: String {
        if hasPrefix("libswift") {
            return String(dropFirst("libswift".count))
        }
        return self
    }
}

#endif
