import Foundation
import MachOKit

extension LoadCommandsProtocol {
    package var text: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == SEG_TEXT
            }
    }

    package var text64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == SEG_TEXT
            }
    }

    package var data: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == SEG_DATA
            }
    }

    package var data64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == SEG_DATA
            }
    }

    package var dataConst: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == "__DATA_CONST"
            }
    }

    package var dataConst64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == "__DATA_CONST"
            }
    }
    
    package var auth64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == "__AUTH"
            }
    }
    
    package var authConst64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == "__AUTH_CONST"
            }
    }
}
