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
            print(typeContextDescriptor)
        }
    }
}
