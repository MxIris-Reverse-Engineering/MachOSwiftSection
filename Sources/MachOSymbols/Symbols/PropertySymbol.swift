import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections

package struct PropertySymbol {
    package enum Kind {
        case getter
        case setter
        case modify
    }

    package let symbol: Symbol

    package let kind: Kind

    package let identifier: String

    package let isStatic: Bool

    package let isInExtension: Bool
}
