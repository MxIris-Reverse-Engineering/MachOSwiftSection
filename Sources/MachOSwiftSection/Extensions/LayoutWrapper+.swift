import Foundation
import MachOKit

extension LayoutWrapper {
    static var layoutSize: Int {
        MemoryLayout<Layout>.size
    }

    var layoutSize: Int {
        MemoryLayout<Layout>.size
    }
}

extension LayoutWrapper {
    static func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }

    func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }

    func layoutOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let pKeyPath: PartialKeyPath<Layout> = keyPath
        return layoutOffset(of: pKeyPath)
    }
}
