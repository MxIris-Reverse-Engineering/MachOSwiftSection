@dynamicMemberLookup
public protocol TopLevelType {
    associatedtype Descriptor
    var descriptor: Descriptor { get }
    subscript<T>(dynamicMember member: KeyPath<Descriptor, T>) -> T { get }
}

extension TopLevelType {
    public subscript<T>(dynamicMember member: KeyPath<Descriptor, T>) -> T {
        return descriptor[keyPath: member]
    }
}
