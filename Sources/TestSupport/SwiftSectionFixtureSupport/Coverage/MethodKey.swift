import Foundation

package struct MethodKey: Hashable, Comparable, CustomStringConvertible {
    package let typeName: String
    package let memberName: String

    package init(typeName: String, memberName: String) {
        self.typeName = typeName
        self.memberName = memberName
    }

    package static func < (left: MethodKey, right: MethodKey) -> Bool {
        if left.typeName != right.typeName { return left.typeName < right.typeName }
        return left.memberName < right.memberName
    }

    package var description: String {
        "\(typeName).\(memberName)"
    }
}
