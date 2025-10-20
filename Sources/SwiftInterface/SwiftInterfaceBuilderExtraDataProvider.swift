import Demangling

public protocol SwiftInterfaceBuilderExtraDataProvider {
    func moduleName(forTypeName typeName: String) -> String?
    func swiftName(forCName cName: String) -> String?
    func opaqueType(forNode node: Node, index: Int?) -> String?
    func setup() async throws
}

extension SwiftInterfaceBuilderExtraDataProvider {
    public func moduleName(forTypeName typeName: String) -> String? { nil }
    public func swiftName(forCName cName: String) -> String? { nil }
    public func opaqueType(forNode node: Node, index: Int?) -> String? { nil }
    public func setup() async throws {}
}
