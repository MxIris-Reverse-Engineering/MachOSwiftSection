import Foundation

package struct MethodKey: Hashable, Comparable, CustomStringConvertible {
    package let typeName: String
    package let memberName: String

    package init(typeName: String, memberName: String) {
        self.typeName = typeName
        self.memberName = memberName
    }

    package static func < (lhs: MethodKey, rhs: MethodKey) -> Bool {
        if lhs.typeName != rhs.typeName { return lhs.typeName < rhs.typeName }
        return lhs.memberName < rhs.memberName
    }

    package var description: String {
        "\(typeName).\(memberName)"
    }
}
