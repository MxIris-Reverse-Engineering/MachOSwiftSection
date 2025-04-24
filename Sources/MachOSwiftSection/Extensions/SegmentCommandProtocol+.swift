import Foundation
import MachOKit

extension SegmentCommandProtocol {
    func __swift5_typeref(in machO: MachOFile) -> SectionType? {
        _section(for: "__swift5_typeref", in: machO)
    }

    func __swift5_reflstr(in machO: MachOImage) -> SectionType? {
        _section(for: "__swift5_reflstr", in: machO)
    }

    func __swift5_fieldmd(in machO: MachOFile) -> SectionType? {
        _section(for: "__swift5_fieldmd", in: machO)
    }

    func __swift5_capture(in machO: MachOImage) -> SectionType? {
        _section(for: "__swift5_capture", in: machO)
    }

    func __swift5_assocty(in machO: MachOFile) -> SectionType? {
        _section(for: "__swift5_assocty", in: machO)
    }

    func __swift5_proto(in machO: MachOImage) -> SectionType? {
        _section(for: "__swift5_proto", in: machO)
    }

    func __swift5_types(in machO: MachOFile) -> SectionType? {
        _section(for: "__swift5_types", in: machO)
    }

    func __swift5_builtin(in machO: MachOImage) -> SectionType? {
        _section(for: "__swift5_builtin", in: machO)
    }

    func __swift5_protos(in machO: MachOFile) -> SectionType? {
        _section(for: "__swift5_protos", in: machO)
    }
}

extension SegmentCommandProtocol {
    func _section(for name: String, in machO: MachOFile) -> SectionType? {
        sections(in: machO).first(
            where: {
                $0.sectionName == name
            }
        )
    }

    func _section(for name: String, in machO: MachOImage) -> SectionType? {
        sections(cmdsStart: machO.cmdsStartPtr).first(
            where: {
                $0.sectionName == name
            }
        )
    }
}
