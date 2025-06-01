import Foundation

package enum RequiredNonOptionalError: Error {
    case requiredNonOptional
}

package func required<T>(_ optional: T?, error: Error? = nil) throws -> T {
    guard let optional else { throw error ?? RequiredNonOptionalError.requiredNonOptional }
    return optional
}
