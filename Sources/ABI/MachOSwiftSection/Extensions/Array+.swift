import Foundation

func + <Element>(left: [Element]?, right: [Element]?) -> [Element] {
    (left ?? []) + (right ?? [])
}

func + <Element>(left: [Element], right: [Element]?) -> [Element] {
    left + (right ?? [])
}

func + <Element>(left: [Element]?, right: [Element]) -> [Element] {
    (left ?? []) + right
}
