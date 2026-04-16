import Testing
import SwiftDump
import MachOSwiftSection
import Demangling
@testable import SwiftInterface

// MARK: - MemberAttributeInferrer Tests

@Suite("MemberAttributeInferrer Tests")
struct MemberAttributeInferrerTests {

    // MARK: - detectFromThunkNode: @objc Detection

    @Test("detectFromThunkNode returns [.objc] when node has .objCAttribute child")
    func detectObjCFromThunkNode() {
        let rootNode = Node.create(kind: .global, children: [
            Node.create(kind: .objCAttribute),
            Node.create(kind: .function, children: [
                Node.create(kind: .structure),
                Node.create(kind: .identifier, text: "someMethod"),
                Node.create(kind: .type),
            ]),
        ])
        let attributes = MemberAttributeInferrer.detectFromThunkNode(rootNode)
        #expect(attributes == [.objc])
    }

    // MARK: - detectFromThunkNode: @nonobjc Detection

    @Test("detectFromThunkNode returns [.nonobjc] when node has .nonObjCAttribute child")
    func detectNonObjCFromThunkNode() {
        let rootNode = Node.create(kind: .global, children: [
            Node.create(kind: .nonObjCAttribute),
            Node.create(kind: .function, children: [
                Node.create(kind: .structure),
                Node.create(kind: .identifier, text: "someMethod"),
                Node.create(kind: .type),
            ]),
        ])
        let attributes = MemberAttributeInferrer.detectFromThunkNode(rootNode)
        #expect(attributes == [.nonobjc])
    }

    // MARK: - detectFromThunkNode: No Attribute

    @Test("detectFromThunkNode returns empty array when node has neither attribute")
    func detectNoAttributeFromThunkNode() {
        let rootNode = Node.create(kind: .global, children: [
            Node.create(kind: .function, children: [
                Node.create(kind: .structure),
                Node.create(kind: .identifier, text: "someMethod"),
                Node.create(kind: .type),
            ]),
        ])
        let attributes = MemberAttributeInferrer.detectFromThunkNode(rootNode)
        #expect(attributes.isEmpty)
    }

    // MARK: - detectFromMethodFlags: dynamic Detection

    @Test("detectFromMethodFlags returns [.dynamic] when isDynamic flag is set")
    func detectDynamicFromMethodFlags() {
        let flags = MethodDescriptorFlags(rawValue: 0x20)
        let attributes = MemberAttributeInferrer.detectFromMethodFlags(flags)
        #expect(attributes == [.dynamic])
    }

    @Test("detectFromMethodFlags returns empty array when isDynamic flag is not set")
    func detectNoDynamicFromMethodFlags() {
        let flags = MethodDescriptorFlags(rawValue: 0x00)
        let attributes = MemberAttributeInferrer.detectFromMethodFlags(flags)
        #expect(attributes.isEmpty)
    }

}
