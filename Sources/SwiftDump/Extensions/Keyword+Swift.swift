import Semantic

extension Keyword {
    enum Swift: String {
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
    }
    
    init(_ keyword: Swift) {
        self.init(keyword.rawValue)
    }
}
