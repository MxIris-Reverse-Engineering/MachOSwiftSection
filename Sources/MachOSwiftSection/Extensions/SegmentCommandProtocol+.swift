import Foundation
import MachOKit

extension SegmentCommandProtocol {
    func __swift5_typeref(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_typeref", in: machOFile)
    }

    func __swift5_reflstr(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_reflstr", in: machOFile)
    }

    func __swift5_fieldmd(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_fieldmd", in: machOFile)
    }

    func __swift5_capture(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_capture", in: machOFile)
    }

    func __swift5_assocty(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_assocty", in: machOFile)
    }

    func __swift5_proto(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_proto", in: machOFile)
    }

    func __swift5_types(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_types", in: machOFile)
    }

    func __swift5_builtin(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_builtin", in: machOFile)
    }

    func __swift5_protos(in machOFile: MachOFile) -> SectionType? {
        _section(for: "__swift5_protos", in: machOFile)
    }
}

extension SegmentCommandProtocol {
    func _section(for name: String, in machOFile: MachOFile) -> SectionType? {
        sections(in: machOFile).first(
            where: {
                $0.sectionName == name
            }
        )
    }

    func _section(for name: String, in machOFile: MachOImage) -> SectionType? {
        sections(cmdsStart: machOFile.cmdsStartPtr).first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
