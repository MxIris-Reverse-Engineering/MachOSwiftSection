import Foundation

public let globalConstant: Int = 42

public var globalVariable: String = "global"

public func globalFunction() -> Int {
    globalConstant
}

public func globalGenericFunction<T: Protocols.ProtocolTest>(_ value: T) -> T.Body {
    value.body
}

public func globalThrowingFunction() throws -> String {
    globalVariable
}

public func globalAsyncFunction() async -> Int {
    globalConstant
}
