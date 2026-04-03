import Testing
import SwiftDump
import Demangling
@testable import SwiftInterface
@_spi(Internals) import MachOSymbols

// MARK: - TypeAttributeInferrer Static Predicate Tests

@Suite("TypeAttributeInferrer Tests")
struct TypeAttributeInferrerTests {

    // MARK: - @propertyWrapper Detection

    @Test("hasWrappedValueMember returns true when wrappedValue field exists")
    func detectPropertyWrapperFromField() {
        let typeNode = Node.create(kind: .type)
        let fields = [
            FieldDefinition(name: "wrappedValue", typeNode: typeNode, flags: FieldFlags()),
        ]
        #expect(TypeAttributeInferrer.hasWrappedValueMember(fields: fields, variables: []))
    }

    @Test("hasWrappedValueMember returns true when wrappedValue variable exists")
    func detectPropertyWrapperFromVariable() {
        let variableNode = Node.create(kind: .variable, children: [
            Node.create(kind: .structure),
            Node.create(kind: .identifier, text: "wrappedValue"),
            Node.create(kind: .type),
        ])
        let dummySymbol = DemangledSymbol(
            symbol: Symbol(offset: 0, name: "$s_wrappedValue"),
            demangledNode: variableNode
        )
        let dummyAccessor = Accessor(
            kind: .getter,
            symbol: dummySymbol,
            methodDescriptor: nil,
            offset: nil,
            vtableOffset: nil
        )
        let variables = [
            VariableDefinition(
                node: variableNode,
                name: "wrappedValue",
                accessors: [dummyAccessor],
                isGlobalOrStatic: false
            ),
        ]
        #expect(TypeAttributeInferrer.hasWrappedValueMember(fields: [], variables: variables))
    }

    @Test("hasWrappedValueMember returns false when no wrappedValue exists")
    func detectPropertyWrapperAbsent() {
        let typeNode = Node.create(kind: .type)
        let fields = [
            FieldDefinition(name: "value", typeNode: typeNode, flags: FieldFlags()),
            FieldDefinition(name: "projectedValue", typeNode: typeNode, flags: FieldFlags()),
        ]
        #expect(!TypeAttributeInferrer.hasWrappedValueMember(fields: fields, variables: []))
    }

    @Test("hasWrappedValueMember returns false for empty members")
    func detectPropertyWrapperEmptyMembers() {
        #expect(!TypeAttributeInferrer.hasWrappedValueMember(fields: [], variables: []))
    }

    // MARK: - @resultBuilder Detection

    @Test("hasBuildBlockMethod returns true when static buildBlock exists")
    func detectResultBuilder() {
        let functions = [
            makeMockFunctionDefinition(name: "buildBlock"),
        ]
        #expect(TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: functions))
    }

    @Test("hasBuildBlockMethod returns false when no buildBlock exists")
    func detectResultBuilderAbsent() {
        let functions = [
            makeMockFunctionDefinition(name: "someOtherMethod"),
        ]
        #expect(!TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: functions))
    }

    @Test("hasBuildBlockMethod returns false for empty static functions")
    func detectResultBuilderEmptyFunctions() {
        #expect(!TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: []))
    }

    @Test("hasBuildBlockMethod returns true with multiple static functions including buildBlock")
    func detectResultBuilderAmongMultipleFunctions() {
        let functions = [
            makeMockFunctionDefinition(name: "buildExpression"),
            makeMockFunctionDefinition(name: "buildBlock"),
            makeMockFunctionDefinition(name: "buildOptional"),
        ]
        #expect(TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: functions))
    }

    // MARK: - @dynamicMemberLookup Detection

    @Test("hasDynamicMemberSubscript returns true when subscript(dynamicMember:) exists")
    func detectDynamicMemberLookup() {
        let subscriptNode = makeDynamicMemberSubscriptNode()
        let subscriptDefinitions = [
            SubscriptDefinition(node: subscriptNode, accessors: [], isStatic: false),
        ]
        #expect(TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: subscriptDefinitions, staticSubscripts: []))
    }

    @Test("hasDynamicMemberSubscript returns true when static subscript(dynamicMember:) exists")
    func detectDynamicMemberLookupFromStaticSubscript() {
        let subscriptNode = makeDynamicMemberSubscriptNode()
        let staticSubscriptDefinitions = [
            SubscriptDefinition(node: subscriptNode, accessors: [], isStatic: true),
        ]
        #expect(TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: [], staticSubscripts: staticSubscriptDefinitions))
    }

    @Test("hasDynamicMemberSubscript returns false when no dynamicMember subscript exists")
    func detectDynamicMemberLookupAbsent() {
        let regularSubscriptNode = Node.create(kind: .subscript, children: [
            Node.create(kind: .structure),
            Node.create(kind: .labelList, children: [
                Node.create(kind: .identifier, text: "key"),
            ]),
            Node.create(kind: .type),
        ])
        let subscriptDefinitions = [
            SubscriptDefinition(node: regularSubscriptNode, accessors: [], isStatic: false),
        ]
        #expect(!TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: subscriptDefinitions, staticSubscripts: []))
    }

    @Test("hasDynamicMemberSubscript returns false for empty subscripts")
    func detectDynamicMemberLookupEmptySubscripts() {
        #expect(!TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: [], staticSubscripts: []))
    }

    @Test("hasDynamicMemberSubscript returns false when labelList has no children")
    func detectDynamicMemberLookupEmptyLabelList() {
        let subscriptNode = Node.create(kind: .subscript, children: [
            Node.create(kind: .structure),
            Node.create(kind: .labelList),
            Node.create(kind: .type),
        ])
        let subscriptDefinitions = [
            SubscriptDefinition(node: subscriptNode, accessors: [], isStatic: false),
        ]
        #expect(!TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: subscriptDefinitions, staticSubscripts: []))
    }

    // MARK: - @dynamicCallable Detection

    @Test("hasDynamicallyCallMethod returns true when dynamicallyCall method exists in instance functions")
    func detectDynamicCallableFromInstanceMethod() {
        let functions = [
            makeMockFunctionDefinition(name: "dynamicallyCall"),
        ]
        #expect(TypeAttributeInferrer.hasDynamicallyCallMethod(functions: functions, staticFunctions: []))
    }

    @Test("hasDynamicallyCallMethod returns true when dynamicallyCall method exists in static functions")
    func detectDynamicCallableFromStaticMethod() {
        let staticFunctions = [
            makeMockFunctionDefinition(name: "dynamicallyCall"),
        ]
        #expect(TypeAttributeInferrer.hasDynamicallyCallMethod(functions: [], staticFunctions: staticFunctions))
    }

    @Test("hasDynamicallyCallMethod returns false when no dynamicallyCall exists")
    func detectDynamicCallableAbsent() {
        let functions = [
            makeMockFunctionDefinition(name: "call"),
            makeMockFunctionDefinition(name: "invoke"),
        ]
        #expect(!TypeAttributeInferrer.hasDynamicallyCallMethod(functions: functions, staticFunctions: []))
    }

    @Test("hasDynamicallyCallMethod returns false for empty functions")
    func detectDynamicCallableEmptyFunctions() {
        #expect(!TypeAttributeInferrer.hasDynamicallyCallMethod(functions: [], staticFunctions: []))
    }

    // MARK: - Combined Detection Tests

    @Test("Multiple attributes can be detected simultaneously via static predicates")
    func multipleAttributeDetection() {
        // A type that is both @propertyWrapper and has dynamicallyCall
        let typeNode = Node.create(kind: .type)
        let fields = [
            FieldDefinition(name: "wrappedValue", typeNode: typeNode, flags: FieldFlags()),
        ]
        let functions = [
            makeMockFunctionDefinition(name: "dynamicallyCall"),
        ]

        #expect(TypeAttributeInferrer.hasWrappedValueMember(fields: fields, variables: []))
        #expect(TypeAttributeInferrer.hasDynamicallyCallMethod(functions: functions, staticFunctions: []))
    }
}

// MARK: - Test Helpers

private func makeMockFunctionDefinition(name: String) -> FunctionDefinition {
    let functionNode = Node.create(kind: .function, children: [
        Node.create(kind: .structure),
        Node.create(kind: .identifier, text: name),
        Node.create(kind: .type),
    ])
    let dummySymbol = DemangledSymbol(
        symbol: Symbol(offset: 0, name: "$s_\(name)"),
        demangledNode: functionNode
    )
    return FunctionDefinition(
        node: functionNode,
        name: name,
        kind: .function,
        symbol: dummySymbol,
        isGlobalOrStatic: true,
        methodDescriptor: nil,
        offset: nil,
        vtableOffset: nil
    )
}

private func makeDynamicMemberSubscriptNode() -> Node {
    return Node.create(kind: .subscript, children: [
        Node.create(kind: .structure),
        Node.create(kind: .labelList, children: [
            Node.create(kind: .identifier, text: "dynamicMember"),
        ]),
        Node.create(kind: .type),
    ])
}
