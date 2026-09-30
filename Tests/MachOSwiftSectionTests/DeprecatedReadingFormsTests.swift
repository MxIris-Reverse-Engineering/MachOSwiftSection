import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The Mach-O and pointer reading forms stay for one release as deprecated
/// forwarders (evolution proposal `reading-context-migration`). They hold no
/// logic of their own, so each test only checks that an old form lands on
/// the context form it should: a mismatch means a forwarder picked the wrong
/// overload, context or reader. Delete this suite together with the
/// forwarders.
@Suite
final class DeprecatedReadingFormsTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    @available(*, deprecated, message: "Exercises the deprecated Mach-O reading forms.")
    @Test func machOFormsAnswerWhatTheContextFormsAnswer() throws {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        #expect(try fileDescriptor.name(in: machOFile) == fileDescriptor.name(in: fileContext))
        #expect(try imageDescriptor.name(in: machOImage) == imageDescriptor.name(in: imageContext))
        #expect(try fileDescriptor.mangledName(in: machOFile) == fileDescriptor.mangledName(in: fileContext))
        #expect(try fileDescriptor.fieldDescriptor(in: machOFile).offset == fileDescriptor.fieldDescriptor(in: fileContext).offset)
        #expect(try Struct(descriptor: fileDescriptor, in: machOFile).descriptor.offset == Struct(descriptor: fileDescriptor, in: fileContext).descriptor.offset)

        let resolvedFromMachO = try ContextDescriptorWrapper.resolve(from: fileDescriptor.offset, in: machOFile) as ContextDescriptorWrapper
        let resolvedFromContext = try ContextDescriptorWrapper.resolve(at: fileDescriptor.offset, in: fileContext) as ContextDescriptorWrapper
        #expect(resolvedFromMachO.contextDescriptor.offset == resolvedFromContext.contextDescriptor.offset)
    }

    @available(*, deprecated, message: "Exercises the deprecated pointer reading forms.")
    @Test func pointerFormsAnswerWhatTheInProcessContextAnswers() throws {
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)

        #expect(try pointerDescriptor.name() == pointerDescriptor.name(in: inProcessContext))
        #expect(try pointerDescriptor.mangledName() == pointerDescriptor.mangledName(in: inProcessContext))
        #expect(try pointerDescriptor.fieldDescriptor().offset == pointerDescriptor.fieldDescriptor(in: inProcessContext).offset)
        #expect(try Struct(descriptor: pointerDescriptor).descriptor.offset == Struct(descriptor: pointerDescriptor, in: inProcessContext).descriptor.offset)
    }

    /// The pointer form of a symbol-or-element pointer used to trap on a
    /// symbol; it now answers the symbol the way the other forms always did.
    @available(*, deprecated, message: "Exercises the deprecated pointer reading forms.")
    @Test func thePointerFormOfABoundSymbolAnswersTheSymbol() throws {
        let symbol = Symbol(offset: 16, name: "$s4Main9StructureVMn")
        let pointer = SymbolOrElementPointer<ContextDescriptorWrapper>.symbol(symbol)
        guard case .symbol(let resolvedSymbol) = try pointer.resolve() else {
            Issue.record("a bound symbol resolved to an element")
            return
        }
        #expect(resolvedSymbol == symbol)
    }
}
