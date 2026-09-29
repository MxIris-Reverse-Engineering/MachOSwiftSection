import Testing
import Demangling
import SwiftDeclaration
@testable import MachOTestingSupport

/// `declaredNameForTesting` is what tests look definitions up by. It exists
/// because `currentName` misnames a function-local type — the case this suite
/// pins first, with the exact shape that made a specialization test pick a
/// local `MemberKey` enum as its `Int` (ReviewAdjudications A52).
@Suite
struct DeclaredNameForTestingTests {
    private func typeName(mangled: String, kind: TypeKind) throws -> TypeName {
        let global = try demangleAsNode(mangled)
        let typeNode = try #require(global.first(of: .type), "\(mangled) demangles to a type")
        return TypeName(node: NodeReference(interning: typeNode), kind: kind)
    }

    @Test func aFunctionLocalTypeAnswersItsOwnName() throws {
        // `MemberKey #1 in Main.foo() -> Swift.Int`
        let local = try typeName(mangled: "$s4Main3fooSiyF9MemberKeyL_OD", kind: .enum)

        #expect(local.declaredNameForTesting == "MemberKey")
        // The display name reads the tail of the enclosing function's
        // signature — the reason tests must not look definitions up by it.
        #expect(local.currentName == "Int")
    }

    @Test func aNestedTypeAnswersItsOwnName() throws {
        let nested = try typeName(mangled: "$s4Main5OuterV5InnerVD", kind: .struct)

        #expect(nested.declaredNameForTesting == "Inner")
    }

    @Test func aPrivateTypeAnswersItsNameWithoutTheDiscriminator() throws {
        // `Main.(Outer in _0123456789ABCDEF0123456789ABCDEF)`
        let privateType = try typeName(mangled: "$s4Main5Outer33_0123456789ABCDEF0123456789ABCDEFLLVD", kind: .struct)

        #expect(privateType.declaredNameForTesting == "Outer")
    }
}
