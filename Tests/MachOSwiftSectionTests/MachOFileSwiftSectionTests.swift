import Testing
import Foundation
import MachOKit
@testable import MachOSwiftSection

enum Error: Swift.Error {
    case notFound
}

@Suite
struct MachOFileSwiftSectionTests {
    let machOFile: MachOFile

    init() throws {
//        let path = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
        let path = "/System/Applications/Freeform.app/Contents/MacOS/Freeform"
//        let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
        let url = URL(fileURLWithPath: path)
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case let .fat(fatFile):
            self.machOFile = try fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case let .machO(machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }
    }

    @Test func protocols() async throws {
        guard let protocolDescriptors = machOFile.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for protocolDescriptor in protocolDescriptors {
            print(try Protocol(descriptor: protocolDescriptor, in: machOFile))
        }
    }

    @Test func protocolConformances() async throws {
        guard let protocolConformanceDescriptors = machOFile.swift.protocolConformanceDescriptors else {
            throw Error.notFound
        }
        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            print(index)
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machOFile))
        }
    }

    @Test func protocolDescriptors() async throws {
        guard let protocolDescriptors = machOFile.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocolDescriptors {
            try print(proto.name(in: machOFile))
        }
    }

    @Test func typeContextDescriptors() async throws {
        try await Dump.dumpTypeContextDescriptors(in: machOFile)
    }
}
