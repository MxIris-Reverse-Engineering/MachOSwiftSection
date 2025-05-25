import Testing
import Foundation
import MachOKit
@testable import MachOSwiftSection

enum Error: Swift.Error {
    case notFound
}

@Suite
struct MachOFileTests {
    let machOFile: MachOFile

    init() throws {
        let path = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
//        let path = "/System/Applications/Freeform.app/Contents/MacOS/Freeform"
//        let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
        let url = URL(fileURLWithPath: path)
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }
    }

    @Test func protocols() async throws {
        let protocolDescriptors = try require(machOFile.swift.protocolDescriptors)
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machOFile))
        }
    }

    @Test func protocolConformances() async throws {
        let protocolConformanceDescriptors = try require(machOFile.swift.protocolConformanceDescriptors)

        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            print(index)
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machOFile))
        }
    }

    @Test func types() async throws {
        let typeContextDescriptors = try require(machOFile.swift.typeContextDescriptors)

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor.flags.kind {
            case .enum:
                let enumDescriptor = try require(typeContextDescriptor.enumDescriptor(in: machOFile))
                let enumType = try Enum(descriptor: enumDescriptor, in: machOFile)
                print(enumType)
            case .struct:
                let structDescriptor = try require(typeContextDescriptor.structDescriptor(in: machOFile))
                let structType = try Struct(descriptor: structDescriptor, in: machOFile)
                print(structType)
            case .class:
                let classDescriptor = try require(typeContextDescriptor.classDescriptor(in: machOFile))
                let classType = try Class(descriptor: classDescriptor, in: machOFile)
                print(classType)
            default:
                break
            }
        }
    }

    @MainActor
    @Test func associatedTypes() throws {
        let associatedTypeDescriptors = try require(machOFile.swift.associatedTypeDescriptors)
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machOFile))
        }
    }

    private func require<T>(_ optional: T?) throws -> T {
        guard let optional else { throw Error.notFound }
        return optional
    }
}
