import Foundation
import Testing
@testable import Demangle


struct NodeTests {
    @Test func testNode() {
        let node = Node(kind: .type, children: [
//            Node(kind: .dependentMemberType, children: [
//                Node(kind: .dependentGenericParamType, children: [
//                    Node(kind: .index, contents: .index(0)),
//                    Node(kind: .index, contents: .index(0)),
//                ], contents: .name("A")),
                Node(kind: .dependentAssociatedTypeRef, children: [
                    Node(kind: .identifier, contents: .name("Tail")),
                    Node(kind: .dynamicSelf, contents: .none),
//                    Node(kind: .type, child: Node(kind: .protocol, children: [
//                        Node(kind: .module, contents: .name("SwiftUI")),
//                        Node(kind: .identifier, contents: .name("TupleProtocol"))
//                    ]))
                ])
//            ]),
        ], contents: .none)
        print(node.print())
    }
}
