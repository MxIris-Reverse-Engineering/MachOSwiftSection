#if os(macOS)

import Foundation
import MachOObjCSection
@preconcurrency import ObjCDump
import FoundationToolbox

final class ObjCInterfaceIndexer<MachO: MachORepresentable & Sendable>: Sendable {
    enum Error: Swift.Error {
        case unsupportedMachO(MachO)
    }

    @Mutex
    var classInfos: [String: [ObjCClassInfo]] = [:]

    @Mutex
    var protocolInfos: [String: [ObjCProtocolInfo]] = [:]

    func index(in machO: MachO) throws {
        var classInfos: [ObjCClassInfo] = []
        var protocolInfos: [ObjCProtocolInfo] = []
        if let machOFile = machO as? MachOFile {
            func addClassInfos(for classes: [any ObjCClassProtocol]?) {
                guard let classes else { return }
                return classInfos.append(contentsOf: classes.compactMap { $0.info(in: machOFile) })
            }
            func addProtocolInfos(for protocols: [any ObjCProtocolProtocol]?) {
                guard let protocols else { return }
                return protocolInfos.append(contentsOf: protocols.compactMap { $0.info(in: machOFile) })
            }
            addClassInfos(for: machOFile.objc.classes64)
            addClassInfos(for: machOFile.objc.classes32)
            addClassInfos(for: machOFile.objc.nonLazyClasses64)
            addClassInfos(for: machOFile.objc.nonLazyClasses32)
            addProtocolInfos(for: machOFile.objc.protocols64)
            addProtocolInfos(for: machOFile.objc.protocols32)
            let image = machOFile.imagePath.lastPathComponent.deletingPathExtension.deletingPathExtension
            self.classInfos[image] = classInfos
            self.protocolInfos[image] = protocolInfos

        } else if let machOImage = machO as? MachOImage {
            func addClassInfos(for classes: [any ObjCClassProtocol]?) {
                guard let classes else { return }
                return classInfos.append(contentsOf: classes.compactMap { $0.info(in: machOImage) })
            }
            func addProtocolInfos(for protocols: [any ObjCProtocolProtocol]?) {
                guard let protocols else { return }
                return protocolInfos.append(contentsOf: protocols.compactMap { $0.info(in: machOImage) })
            }
            addClassInfos(for: machOImage.objc.classes64)
            addClassInfos(for: machOImage.objc.classes32)
            addClassInfos(for: machOImage.objc.nonLazyClasses64)
            addClassInfos(for: machOImage.objc.nonLazyClasses32)
            addProtocolInfos(for: machOImage.objc.protocols64)
            addProtocolInfos(for: machOImage.objc.protocols32)
            if let path = machOImage.path {
                let image = path.lastPathComponent.deletingPathExtension.deletingPathExtension
                self.classInfos[image] = classInfos
                self.protocolInfos[image] = protocolInfos
            }
        } else {
            throw Error.unsupportedMachO(machO)
        }
    }
}


#endif
