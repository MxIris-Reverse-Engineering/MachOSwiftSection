import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

@Suite
final class FixtureLoadingProbeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @Test func machOFileSwiftSectionParses() async throws {
        let typeContextDescriptors = try machOFile.swift.typeContextDescriptors
        #expect(!typeContextDescriptors.isEmpty, "fixture must contain at least one type")
    }

    @Test func machOImageSwiftSectionParses() async throws {
        let typeContextDescriptors = try machOImage.swift.typeContextDescriptors
        #expect(!typeContextDescriptors.isEmpty, "fixture image must contain at least one type")
    }

    @Test func threeReadersSeeSameTypeCount() async throws {
        let fileCount = try machOFile.swift.typeContextDescriptors.count
        let imageCount = try machOImage.swift.typeContextDescriptors.count
        #expect(fileCount == imageCount, "MachOFile and MachOImage disagree on type count")
    }
}
