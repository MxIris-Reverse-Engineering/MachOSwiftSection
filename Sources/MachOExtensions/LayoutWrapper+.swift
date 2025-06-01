import Foundation
import MachOKit

extension LayoutWrapper {
    package static var layoutSize: Int {
        MemoryLayout<Layout>.size
    }

    package var layoutSize: Int {
        MemoryLayout<Layout>.size
    }
}

extension LayoutWrapper {
    package static func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }

    package func layoutOffset(of key: PartialKeyPath<Layout>) -> Int {
        MemoryLayout<Layout>.offset(of: key)! // swiftlint:disable:this force_unwrapping
    }

    package func layoutOffset<T>(of keyPath: KeyPath<Layout, T>) -> Int {
        let pKeyPath: PartialKeyPath<Layout> = keyPath
        return layoutOffset(of: pKeyPath)
    }
}
