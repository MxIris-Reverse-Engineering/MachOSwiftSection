@_transparent
@_alwaysEmitIntoClient
public func or<T: ~Copyable>(
    _ optional: consuming T?,
    _ defaultValue: @autoclosure () async throws -> T? // FIXME: typed throws
) async rethrows -> T? {
    // FIXME: We want this to support nonescapable `T` types.
    // To implement that, we need to be able to express that the result's lifetime
    // is limited to the intersection of `optional` and the result of
    // `defaultValue`:
    //    @lifetime(optional, defaultValue.result)
    switch consume optional {
    case .some(let value):
        return value
    case .none:
        return try await defaultValue()
    }
}

@_transparent
@_alwaysEmitIntoClient
public func or<T: ~Copyable>(
    _ optional: consuming T?,
    _ defaultValue: @autoclosure () async throws -> T // FIXME: typed throws
) async rethrows -> T {
    // FIXME: We want this to support nonescapable `T` types.
    // To implement that, we need to be able to express that the result's lifetime
    // is limited to the intersection of `optional` and the result of
    // `defaultValue`:
    //    @lifetime(optional, defaultValue.result)
    switch consume optional {
    case .some(let value):
        return value
    case .none:
        return try await defaultValue()
    }
}
