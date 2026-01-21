import Foundation
import MachOKit

extension MachORepresentable {
    package func _section(
        for name: String
    ) -> (any SectionProtocol)? {
        sections.first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
