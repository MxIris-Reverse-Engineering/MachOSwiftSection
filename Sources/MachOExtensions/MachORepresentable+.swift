import Foundation
import MachOKit
import MachOMacro

@MachOImageAllMembersGenerator
extension MachORepresentable {
    package func _section(
        for name: String,
        in machOFile: MachOFile
    ) -> (any SectionProtocol)? {
        sections.first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
