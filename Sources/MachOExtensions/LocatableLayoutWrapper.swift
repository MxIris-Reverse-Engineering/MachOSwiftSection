import MachOKit

public protocol LocatableLayoutWrapper: LayoutWrapper, Sendable {
    var offset: Int { get }

    init(layout: Layout, offset: Int)
}

extension LocatableLayoutWrapper {
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }
}
