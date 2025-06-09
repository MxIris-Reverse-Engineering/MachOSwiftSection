import Foundation
import Testing
@testable import MachOSwiftSection

@Suite
struct LayoutTests {
    @Test func contextDescriptor() async throws {
        #expect(ContextDescriptor.Layout.offset(of: .flags) == 0)
        #expect(ContextDescriptor.Layout.offset(of: .parent) == 4)
    }

    @Test func typeContextDescriptor() async throws {
        #expect(TypeContextDescriptor.Layout.offset(of: .name) == 8)
        #expect(TypeContextDescriptor.Layout.offset(of: .accessFunctionPtr) == 12)
        #expect(TypeContextDescriptor.Layout.offset(of: .fieldDescriptor) == 16)
        print(ClassMetadataObjCInterop.Layout.offset(of: .instanceAddressPoint))
    }
}
