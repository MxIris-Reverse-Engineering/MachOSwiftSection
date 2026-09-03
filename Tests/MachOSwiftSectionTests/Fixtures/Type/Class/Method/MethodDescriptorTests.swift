import Foundation
import Testing
import MachOFoundation
import SwiftInspection
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `MethodDescriptor`.
///
/// The Suite picks the first vtable entry from `Classes.ClassTest`, then
/// asserts cross-reader equality on the descriptor's offset, the
/// `flags.rawValue`, and the implementation offset the relative pointer
/// resolves to (pinned as a baseline literal; the ReadingContext leg must
/// report the same location as a context address).
@Suite
final class MethodDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDescriptor"
    static var registeredTestMethodNames: Set<String> {
        MethodDescriptorBaseline.registeredTestMethodNames
    }

    /// Helper: load the first vtable entry of `Classes.ClassTest` from
    /// each reader.
    private func loadFirstMethods() throws -> (file: MethodDescriptor, image: MethodDescriptor) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileMethod = try required(fileClass.methodDescriptors.first)
        let imageMethod = try required(imageClass.methodDescriptors.first)
        return (file: fileMethod, image: imageMethod)
    }

    @Test func offset() async throws {
        let methods = try loadFirstMethods()
        let result = try acrossAllReaders(
            file: { methods.file.offset },
            image: { methods.image.offset }
        )
        #expect(result == MethodDescriptorBaseline.firstClassTestMethod.offset)
    }

    @Test func layout() async throws {
        let methods = try loadFirstMethods()
        let flagsRaw = try acrossAllReaders(
            file: { methods.file.layout.flags.rawValue },
            image: { methods.image.layout.flags.rawValue }
        )
        #expect(flagsRaw == MethodDescriptorBaseline.firstClassTestMethod.layoutFlagsRawValue)
    }

    /// `implementationOffset` is pure relative-pointer arithmetic: pinned as
    /// a literal and identical across readers.
    @Test func implementationOffset() async throws {
        let methods = try loadFirstMethods()
        let result = try acrossAllReaders(
            file: { methods.file.implementationOffset },
            image: { methods.image.implementationOffset }
        )
        #expect(result == MethodDescriptorBaseline.firstClassTestMethod.implementationOffset)
    }

    /// The `ReadingContext` leg reports the same location as a context
    /// address (a file offset for `MachOContext`). Its predecessor,
    /// `implementationSymbols(in: context)`, had no symbol service to consult
    /// and read the implementation's machine code as a `Symbols` value —
    /// its `offset` came back as the first eight code bytes (evolution
    /// proposal `self-contained-abi-layer`). This equality is what that
    /// leg could never satisfy.
    @Test func implementationAddress() async throws {
        let methods = try loadFirstMethods()
        let fileAddress = try methods.file.implementationAddress(in: fileContext)
        let imageAddress = try methods.image.implementationAddress(in: imageContext)
        #expect(fileAddress == methods.file.implementationOffset)
        #expect(imageAddress == methods.image.implementationOffset)
        #expect(imageAddress == MethodDescriptorBaseline.firstClassTestMethod.implementationOffset)
    }

    /// Symbol attribution lives one layer up (SwiftInspection): it is the
    /// symbol index's answer for the offset the ABI layer reports, nothing
    /// more. The first vtable entry of ClassTest resolves to a real symbol.
    @Test func implementationSymbolsAttributeTheReportedOffset() async throws {
        let methods = try loadFirstMethods()
        let offset = try #require(methods.file.implementationOffset)
        let expectedNames = machOFile.symbols(offset: offset)?.map(\.name)
        #expect(expectedNames?.isEmpty == false)
        #expect(methods.file.implementationSymbols(in: machOFile)?.map(\.name) == expectedNames)
        #expect(methods.image.implementationSymbols(in: machOImage)?.map(\.name) == machOImage.symbols(offset: offset)?.map(\.name))
    }
}
