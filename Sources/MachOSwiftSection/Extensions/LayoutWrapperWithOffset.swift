import MachOKit

public protocol LayoutWrapperWithOffset: LayoutWrapper {
    var offset: Int { get }
    func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int
    init(offset: Int, layout: Layout)
}

extension LayoutWrapperWithOffset {
    public func offset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        return offset + MemoryLayout<Layout>.offset(of: keyPath)!
    }
    
    public func address(of keyPath: KeyPath<Layout, RelativeOffset>) -> UInt64 {
        return numericCast(offset(of: keyPath) + layout[keyPath: keyPath].cast())
    }
}
