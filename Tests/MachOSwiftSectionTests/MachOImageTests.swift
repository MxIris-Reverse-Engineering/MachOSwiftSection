import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection

@Suite
struct MachOImageTests {
    let machOImage: MachOImage

    init() {
        self.machOImage = MachOImage(name: "Foundation")!
    }

    @Test func types() throws {
        let typeContextDescriptors = try required(machOImage.swift.typeContextDescriptors)

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor.flags.kind {
            case .enum:
                let enumDescriptor = try required(typeContextDescriptor.enumDescriptor(in: machOImage))
                let enumType = try Enum(descriptor: enumDescriptor, in: machOImage)
                try print(enumType.dump(using: printOptions, in: machOImage))
            case .struct:
                let structDescriptor = try required(typeContextDescriptor.structDescriptor(in: machOImage))
                let structType = try Struct(descriptor: structDescriptor, in: machOImage)
                try print(structType.dump(using: printOptions, in: machOImage))
            case .class:
                let classDescriptor = try required(typeContextDescriptor.classDescriptor(in: machOImage))
                let classType = try Class(descriptor: classDescriptor, in: machOImage)
                try print(classType.dump(using: printOptions, in: machOImage))
            default:
                break
            }
        }
    }
}
