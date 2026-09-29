import Semantic
import SwiftInspection

extension CustomObjCClassName.Attribute {
    /// The keyword a renamed class's attribute prints with (evolution proposal
    /// `objc-custom-class-name`); the runtime name follows in parentheses.
    package var keyword: Keyword.Swift {
        switch self {
        case .objc:
            return .atObjc
        case .objcRuntimeName:
            return .atObjCRuntimeName
        }
    }
}
