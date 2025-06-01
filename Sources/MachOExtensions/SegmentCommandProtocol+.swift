import Foundation
import MachOKit

extension SegmentCommandProtocol {
    package func _section(for name: String, in machOFile: MachOFile) -> SectionType? {
        sections(in: machOFile).first(
            where: {
                $0.sectionName == name
            }
        )
    }

    package func _section(for name: String, in machOFile: MachOImage) -> SectionType? {
        sections(cmdsStart: machOFile.cmdsStartPtr).first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
