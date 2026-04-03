import Semantic

extension Keyword {
    package enum Swift: String {
        case `associatedtype`
        case `extension`
        case `typealias`
        case `class`
        case `actor`
        case `struct`
        case `enum`
        case `lazy`
        case `weak`
        case `override`
        case `static`
        case `dynamic`
        case `func`
        case `case`
        case `let`
        case `var`
        case `where`
        case `indirect`
        case `protocol`
        case `Self`
        case `each`
        case `repeat`
        case atObjc = "@objc"
        case atNonobjc = "@nonobjc"
        case atFrozen = "@frozen"
        case atInlinable = "@inlinable"
        case atUsableFromInline = "@usableFromInline"
        case atPropertyWrapper = "@propertyWrapper"
        case atResultBuilder = "@resultBuilder"
        case atDynamicMemberLookup = "@dynamicMemberLookup"
        case atDynamicCallable = "@dynamicCallable"
        case atRetroactive = "@retroactive"
    }

    package init(_ keyword: Swift) {
        self.init(keyword.rawValue)
    }
}
