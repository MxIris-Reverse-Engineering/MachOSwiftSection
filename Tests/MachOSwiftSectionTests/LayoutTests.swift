import Foundation
import Testing
@testable import MachOSwiftSection

struct LayoutTests {
    
    @Test func test() async throws {
        print(ContextDescriptor.Layout.offset(of: .flags))
        print(ContextDescriptor.Layout.offset(of: .parent))
        print(TypeContextDescriptor.Layout.offset(of: .name))
        print(TypeContextDescriptor.Layout.offset(of: .accessFunctionPtr))
        print(TypeContextDescriptor.Layout.offset(of: .fieldDescriptor))
    }
}
