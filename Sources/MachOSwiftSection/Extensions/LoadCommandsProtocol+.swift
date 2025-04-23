//
//  LoadCommandsProtocol+.swift
//
//
//  Created by p-x9 on 2024/08/01
//  
//

import Foundation
@_spi(Support) import MachOKit

extension LoadCommandsProtocol {
    var text: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == SEG_TEXT
            }
    }

    var text64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == SEG_TEXT
            }
    }

    var data: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == SEG_DATA
            }
    }

    var data64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == SEG_DATA
            }
    }

    var dataConst: SegmentCommand? {
        infos(of: LoadCommand.segment)
            .first {
                $0.segname == "__DATA_CONST"
            }
    }

    var dataConst64: SegmentCommand64? {
        infos(of: LoadCommand.segment64)
            .first {
                $0.segname == "__DATA_CONST"
            }
    }
}
