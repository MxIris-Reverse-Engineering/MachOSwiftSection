protocol RelativePointerOptional: ExpressibleByNilLiteral {
    associatedtype Wrapped
}

extension Optional: RelativePointerOptional {}
