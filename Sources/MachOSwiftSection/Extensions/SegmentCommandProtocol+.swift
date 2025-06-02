import MachOKit

extension SegmentCommandProtocol {
    func _section(for swiftSection: MachOSwiftSectionName, in machOFile: MachOFile) -> SectionType? {
        _section(for: swiftSection.rawValue, in: machOFile)
    }

    func _section(for swiftSection: MachOSwiftSectionName, in machOFile: MachOImage) -> SectionType? {
        _section(for: swiftSection.rawValue, in: machOFile)
    }
}
