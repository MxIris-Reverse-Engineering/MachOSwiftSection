import Foundation

func + <Element>(lhs: [Element]?, rhs: [Element]?) -> [Element] {
    (lhs ?? []) + (rhs ?? [])
}

func + <Element>(lhs: [Element], rhs: [Element]?) -> [Element] {
    lhs + (rhs ?? [])
}

func + <Element>(lhs: [Element]?, rhs: [Element]) -> [Element] {
    (lhs ?? []) + rhs
}
