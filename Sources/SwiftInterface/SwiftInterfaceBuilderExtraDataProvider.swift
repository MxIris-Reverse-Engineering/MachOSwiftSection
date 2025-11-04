import Demangling

public protocol SwiftInterfaceBuilderExtraDataProvider {
    func moduleName(forTypeName typeName: String) async -> String?
    func swiftName(forCName cName: String) async -> String?
    func opaqueType(forNode node: Node, index: Int?) async -> String?
    func setup() async throws
}

extension SwiftInterfaceBuilderExtraDataProvider {
    public func moduleName(forTypeName typeName: String) async -> String? { nil }
    public func swiftName(forCName cName: String) async -> String? { nil }
    public func opaqueType(forNode node: Node, index: Int?) async -> String? { nil }
    public func setup() async throws {}
}
