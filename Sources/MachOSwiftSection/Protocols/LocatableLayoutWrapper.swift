import MachOKit

public protocol LocatableLayoutWrapper: LayoutWrapper, ResolvableElement {
    var offset: Int { get }

    init(layout: Layout, offset: Int)
}

extension LocatableLayoutWrapper {
    public func fileOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }

    public func resolvedRelativeOffset(of keyPath: KeyPath<Layout, RelativeOffset>) -> Int {
        return numericCast(fileOffset(of: keyPath) + layout[keyPath: keyPath].cast())
    }
}

