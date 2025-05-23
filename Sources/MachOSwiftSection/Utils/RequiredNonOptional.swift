import Foundation

enum RequiredNonOptionalError: Error {
    case requiredNonOptional
}

func required<T>(_ optional: T?) throws -> T {
    guard let optional else { throw RequiredNonOptionalError.requiredNonOptional }
    return optional
}
