import Testing
import Foundation
import MachOKit
@testable import MachOSwiftSection

@Suite
struct MachOFileTests {
    let machOFile: MachOFile

    init() throws {
//        let path = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
//        let path = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework/Versions/A/ScreenContinuityUI"
        let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
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
        let protocolDescriptors = try required(machOFile.swift.protocolDescriptors)
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machOFile).dump(using: printOptions, in: machOFile))
        }
    }

    @Test func protocolConformances() async throws {
        let protocolConformanceDescriptors = try required(machOFile.swift.protocolConformanceDescriptors)

        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            print(index)
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machOFile).dump(using: printOptions, in: machOFile))
        }
    }

    @Test func types() async throws {
        let typeContextDescriptors = try required(machOFile.swift.typeContextDescriptors)

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor.flags.kind {
            case .enum:
                let enumDescriptor = try required(typeContextDescriptor.enumDescriptor(in: machOFile))
                let enumType = try Enum(descriptor: enumDescriptor, in: machOFile)
                try print(enumType.dump(using: printOptions, in: machOFile))
            case .struct:
                let structDescriptor = try required(typeContextDescriptor.structDescriptor(in: machOFile))
                let structType = try Struct(descriptor: structDescriptor, in: machOFile)
                try print(structType.dump(using: printOptions, in: machOFile))
            case .class:
                let classDescriptor = try required(typeContextDescriptor.classDescriptor(in: machOFile))
                let classType = try Class(descriptor: classDescriptor, in: machOFile)
                try print(classType.dump(using: printOptions, in: machOFile))
            default:
                break
            }
        }
    }

    @MainActor
    @Test func associatedTypes() throws {
        let associatedTypeDescriptors = try required(machOFile.swift.associatedTypeDescriptors)
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machOFile).dump(using: printOptions, in: machOFile))
        }
    }
}
