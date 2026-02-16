import Foundation
import Testing
import MachOKit
import Dependencies
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInterface
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) @testable import MachOCaches

protocol SwiftInterfaceBuilderTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SwiftInterfaceBuilderTests {
    var rootDirectory: URL {
        .documentsDirectory.appending(path: "SwiftInterfaceTests")
    }

    var builderConfiguration: SwiftInterfaceBuilderConfiguration {
        SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: false
            ),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printTypeLayout: true,
            )
        )
    }

    func buildString(in machO: MachOFile) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        print(result.string)
    }

    func buildString(in machO: MachOImage) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        print(result.string)
    }

    func buildFile(in machO: MachOFile) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [OSLogEventHandler()], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.loadCommands.buildVersionCommand!)-\(machO.imagePath.lastPathComponent)-FileDump.swiftinterface"), atomically: true, encoding: .utf8)
    }

    func buildFile(in machO: MachOImage) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: builderConfiguration, eventHandlers: [OSLogEventHandler()], in: machO)
        let clock = ContinuousClock()
        let duration = try await clock.measure {
            try await builder.prepare()
        }
        print(duration)
        let result = try await builder.printRoot()
        try rootDirectory.createDirectoryIfNeeded()
        try result.string.write(to: rootDirectory.appending(path: "\(machO.loadCommands.buildVersionCommand!)-\(machO.imagePath.lastPathComponent)-ImageDump.swiftinterface"), atomically: true, encoding: .utf8)
    }
}

@Suite
enum SwiftInterfaceBuilderTestSuite {
    class DyldCacheTests: MachOTestingSupport.DyldCacheTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var cacheImageName: MachOImageName {
            .SwiftUI
        }

        override class var cachePath: DyldSharedCachePath {
            .current
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFileInCache)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFileInCache)
        }
    }

    class MachOFileTests: MachOTestingSupport.MachOFileTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var fileName: MachOFileName {
            .iOS_26_2_Simulator_SwiftUICore
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFile)
        }
    }

    class MachOImageTests: MachOTestingSupport.MachOImageTests, SwiftInterfaceBuilderTests, @unchecked Sendable {
        override class var imageName: MachOImageName {
            .SwiftUI
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOImage)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOImage)
        }
    }

    class XcodeMachOFileTests: MachOTestingSupport.XcodeMachOFileTests, SwiftInterfaceBuilderTests {
        override class var fileName: XcodeMachOFileName {
            .sharedFrameworks(.SourceEditor)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildFile() async throws {
            try await buildFile(in: machOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func buildString() async throws {
            try await buildString(in: machOFile)
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

extension BuildVersionCommand: @retroactive CustomStringConvertible {
    public var description: String {
        "\(platform.stringValue)-\(sdk)"
    }
}

extension MachOKit.Platform {
    var stringValue: String {
        switch self {
        case .unknown:
            "Unknown"
        case .any:
            "Any"
        case .macOS:
            "macOS"
        case .iOS:
            "iOS"
        case .tvOS:
            "tvOS"
        case .watchOS:
            "watchOS"
        case .bridgeOS:
            "bridgeOS"
        case .macCatalyst:
            "macCatalyst"
        case .iOSSimulator:
            "iOSSimulator"
        case .tvOSSimulator:
            "tvOSSimulator"
        case .watchOSSimulator:
            "watchOSSimulator"
        case .driverKit:
            "DriverKit"
        case .visionOS:
            "visionOS"
        case .visionOSSimulator:
            "visionOSSimulator"
        case .firmware:
            "Firmware"
        case .sepOS:
            "sepOS"
        case .macOSExclaveCore:
            "macOSExclaveCore"
        case .macOSExclaveKit:
            "macOSExclaveKit"
        case .iOSExclaveCore:
            "iOSExclaveCore"
        case .iOSExclaveKit:
            "iOSExclaveKit"
        case .tvOSExclaveCore:
            "tvOSExclaveCore"
        case .tvOSExclaveKit:
            "tvOSExclaveKit"
        case .watchOSExclaveCore:
            "watchOSExclaveCore"
        case .watchOSExclaveKit:
            "watchOSExclaveKit"
        case .visionOSExclaveCore:
            "visionOSExclaveCore"
        case .visionOSExclaveKit:
            "visionOSExclaveKit"
        }
    }
}
