import Foundation
import MachOKit
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

extension CrossReferenceAnalyzer {
    /// What the unslid `address` is: inside which function, a stub and
    /// where it leads, a pointer slot and what it holds, a string, the
    /// nearest symbol — or nothing any image maps.
    ///
    /// The images of one shared cache share their unslid addresses; a set
    /// of standalone files each keep their own, so an address two of them
    /// both hold is read in the first. ``symbolication(of:inImageAt:)``
    /// names the image.
    public func symbolication(of address: UInt64) -> AddressSymbolication {
        symbolication(of: address, inImageAt: nil)
    }

    /// What the unslid `address` of the image at `imageIndex` is.
    public func symbolication(of address: UInt64, inImageAt imageIndex: Int?) -> AddressSymbolication {
        // The language-free structure from the core; what the Objective-C
        // and Swift layers know — a selector, a class, an instance variable,
        // a type, a function's name — added here.
        let place = imageSet.place(ofUnslid: address, inImageAt: imageIndex, slotSectionNames: Self.objectiveCSlotSectionNames)
        let meaning: AddressSymbolication.Meaning
        switch place.content {
        case .function(let index):
            let placeImageIndex = place.imageIndex!
            let table = functionTable(ofImageAt: placeImageIndex)
            let function = codeFunction(at: index, in: table)
            meaning = .function(start: function.location, name: function.name.map(Self.spelling(of:)), offset: address - function.location.address)
        case .trampoline(let hops, let target):
            meaning = .stub(hops: hops, target: publicTarget(of: target, lastHop: hops.last ?? address))
        case .otherCode:
            meaning = otherCodeMeaning(at: address, inImageAt: place.imageIndex!)
        case .slot(let content):
            if place.sectionName == "__objc_ivar", let imageIndex = place.imageIndex {
                meaning = instanceVariableOffsetMeaning(at: address, inImageAt: imageIndex)
            } else {
                let kind = Self.slotKind(ofSectionNamed: place.sectionName)
                meaning = .pointerSlot(kind, target: slotTarget(content, kind: kind))
            }
        case .string(.cString(let characters)):
            meaning = .cString(characters)
        case .string(.constantString(let characters)):
            meaning = .constantString(characters)
        case .data(let nearestSymbol):
            meaning = nearestSymbol.map { .symbol(name: $0.name, offset: $0.offset) } ?? .data
        case .unmapped:
            meaning = .unmapped
        }
        return AddressSymbolication(
            address: address,
            imagePath: place.imageIndex.map { imagePaths[$0] },
            segmentName: place.segmentName,
            sectionName: place.sectionName,
            meaning: meaning
        )
    }

    /// The Objective-C sections whose words are pointer slots: the core
    /// reads them, the Objective-C layer says what they hold.
    static let objectiveCSlotSectionNames: Set<String> = ["__objc_selrefs", "__objc_classrefs", "__objc_superrefs", "__objc_protorefs", "__objc_ivar"]

    private static func slotKind(ofSectionNamed sectionName: String?) -> AddressSymbolication.PointerSlotKind {
        switch sectionName {
        case "__objc_selrefs": .selectorReference
        case "__objc_classrefs": .classReference
        case "__objc_superrefs": .superclassReference
        case "__objc_protorefs": .protocolReference
        case "__objc_ivar": .instanceVariableOffset
        default: .globalOffsetTable
        }
    }

    static func spelling(of name: CodeFunction.Name) -> String {
        name.spelling
    }

    /// A call target the core resolved, as a reference target: a selector
    /// a cache-shared stub puts in `x1` is the message it sends.
    private func publicTarget(of target: ResolvedCallTarget, lastHop: UInt64) -> CodeReferenceTarget {
        switch target {
        case .function(let location):
            return .function(location)
        case .importedSymbol(let name):
            return .importedSymbol(name: String(cString: name))
        case .registerSettingTrampoline(register: 1, let value):
            if let selector = cString(atRuntimeAddress: UInt(value)) { return .messageSend(selector: selector, receiver: .unknown) }
            return .unrecognized(address: lastHop)
        case .registerSettingTrampoline, .unrecognized:
            return .unrecognized(address: lastHop)
        }
    }

    /// Code in a section that is no `__text` and no symbol stub section:
    /// an image's own selector stub, which names the message it sends.
    private func otherCodeMeaning(at address: UInt64, inImageAt imageIndex: Int) -> AddressSymbolication.Meaning {
        let table = functionTable(ofImageAt: imageIndex)
        let sections = ObjCImageSections.of(table)
        if let stubRange = sections.stubRange, stubRange.contains(address) {
            let stubAddress = sections.stubSelectors.keys.filter { $0 <= address }.max() ?? address
            if let selector = sections.stubSelectors[stubAddress] {
                return .stub(hops: [stubAddress], target: .messageSend(selector: String(cString: selector), receiver: .unknown))
            }
        }
        if let nearestSymbol = imageSet.nearestSymbol(toUnslid: address, inImageAt: imageIndex) {
            return .symbol(name: nearestSymbol.name, offset: nearestSymbol.offset)
        }
        return .data
    }

    private func instanceVariableOffsetMeaning(at address: UInt64, inImageAt imageIndex: Int) -> AddressSymbolication.Meaning {
        let table = functionTable(ofImageAt: imageIndex)
        let slot = address & ~UInt64(3)
        if let variable = ObjCInstanceVariableNames.of(table).instanceVariablesBySlot[slot] {
            return .pointerSlot(.instanceVariableOffset, target: .objectiveCInstanceVariable(className: variable.className, name: variable.name))
        }
        return .pointerSlot(.instanceVariableOffset, target: .unrecognized(address: slot))
    }

    /// What a slot holds, as a reference target: a function, a class, a
    /// Swift type, a selector a selector reference names, a protocol by its
    /// name, an imported symbol — or an address the layers know nothing of.
    private func slotTarget(_ content: SlotContent?, kind: AddressSymbolication.PointerSlotKind) -> CodeReferenceTarget {
        switch content {
        case .importedSymbol(let name)?:
            return .importedSymbol(name: name)
        case .address(let value)?:
            switch kind {
            case .selectorReference:
                if let selector = cString(atRuntimeAddress: value) { return .selector(selector) }
            case .protocolReference:
                // `protocol_t`: `isa`, then the name.
                if let nameAddress = memory.pointer(at: value &+ 8), let name = cString(atRuntimeAddress: nameAddress) { return .cString(name) }
            default:
                break
            }
            if let location = imageSet.location(ofRuntimeAddress: value) {
                if swiftTypeIndex(ofImageAt: location.imageIndex).describesType(descriptorAt: value) { return .swiftType(descriptor: location) }
                return .function(location)
            }
            if let imageIndex = imageSet.imageIndex(containingDataAddress: value),
               let classObject = objectiveCClassIndex(ofImageAt: imageIndex).classObject(atRuntimeAddress: value) {
                return .objectiveCClass(name: classObject.name, location: classObject.location)
            }
            return .unrecognized(address: imageSet.imageIndex(containingDataAddress: value).map { imageSet.images[$0].unslidAddress(ofRuntime: value) } ?? UInt64(value))
        case nil:
            return .unrecognized(address: 0)
        }
    }

    /// Every name the image's export trie gives the function at `location`.
    func exportedNames(at location: CodeLocation) -> [String] {
        ExportedFunctionNames.of(functionTable(ofImageAt: location.imageIndex)).namesByAddress[location.address] ?? []
    }

    private func cString(atRuntimeAddress address: UInt) -> String? {
        guard address != 0, isMapped(runtimeAddress: address, length: 1), let characters = memory.typedPointer(to: CChar.self, at: address, length: 1) else { return nil }
        return String(cString: characters)
    }
}
