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

    // MARK: - detectFromSpecializationNode: @inlinable Detection

    @Test("detectFromSpecializationNode returns [.inlinable] when node has .isSerialized child")
    func detectInlinableFromSpecializationNode() {
        let node = Node.create(kind: .genericSpecialization, children: [
            Node.create(kind: .isSerialized),
            Node.create(kind: .type, children: [
                Node.create(kind: .structure),
            ]),
        ])
        let attributes = MemberAttributeInferrer.detectFromSpecializationNode(node)
        #expect(attributes == [.inlinable])
    }

    @Test("detectFromSpecializationNode returns empty array when node has no .isSerialized child")
    func detectNoInlinableFromSpecializationNode() {
        let node = Node.create(kind: .genericSpecialization, children: [
            Node.create(kind: .type, children: [
                Node.create(kind: .structure),
            ]),
        ])
        let attributes = MemberAttributeInferrer.detectFromSpecializationNode(node)
        #expect(attributes.isEmpty)
    }

    // MARK: - hasSerializedChild: Recursive Detection

    @Test("hasSerializedChild returns true when .isSerialized is nested deep in the tree")
    func detectSerializedChildNestedDeep() {
        let deeplyNestedNode = Node.create(kind: .global, children: [
            Node.create(kind: .genericSpecialization, children: [
                Node.create(kind: .type, children: [
                    Node.create(kind: .isSerialized),
                ]),
            ]),
        ])
        #expect(MemberAttributeInferrer.hasSerializedChild(deeplyNestedNode))
    }

    @Test("hasSerializedChild returns false when .isSerialized is not present anywhere")
    func detectNoSerializedChild() {
        let nodeWithoutSerialized = Node.create(kind: .global, children: [
            Node.create(kind: .genericSpecialization, children: [
                Node.create(kind: .type, children: [
                    Node.create(kind: .structure),
                ]),
            ]),
        ])
        #expect(!MemberAttributeInferrer.hasSerializedChild(nodeWithoutSerialized))
    }

    @Test("hasSerializedChild returns true when the node itself is .isSerialized")
    func detectSerializedChildDirectMatch() {
        let serializedNode = Node.create(kind: .isSerialized)
        #expect(MemberAttributeInferrer.hasSerializedChild(serializedNode))
    }
}
