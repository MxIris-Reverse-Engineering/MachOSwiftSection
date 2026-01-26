import Demangling

public protocol SwiftInterfaceBuilderExtraDataProvider: TypeNameResolvable {
    func setup() async throws
}

extension SwiftInterfaceBuilderExtraDataProvider {
    public func setup() async throws {}
}
