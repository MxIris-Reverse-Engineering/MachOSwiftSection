import Foundation
import Testing
@testable import Demangle

struct NodeTests {
    @Test func testNode() {
        let node = Node(kind: .type, contents: .none) {
            Node(kind: .dependentMemberType) {
                Node(kind: .dependentGenericParamType, contents: .text("A")) {
                    Node(kind: .index, contents: .index(0))
                    Node(kind: .index, contents: .index(0))
                }
                Node(kind: .dependentAssociatedTypeRef) {
                    Node(kind: .identifier, contents: .text("Tail"))
                    Node(kind: .dynamicSelf)
                    Node(kind: .type) {
                        Node(kind: .protocol) {
                            Node(kind: .module, contents: .text("SwiftUI"))
                            Node(kind: .identifier, contents: .text("TupleProtocol"))
                        }
                    }
                }
            }
        }
        print(node.first(of: .type))
    }
}
