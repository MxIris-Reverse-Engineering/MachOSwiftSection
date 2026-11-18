import Foundation
import MachOKit
import MachOObjCSection
import CrossReferenceCore

/// Every method implementation the image's own class and category lists
/// name, by unslid address: a name for a function the symbol table and the
/// export trie leave unnamed. Kept on the image's function table, read when
/// a function is named, never during a scan — reading AppKit's method lists
/// alone takes 42–86 ms.
///
/// A shared cache attaches other images' category lists to a class's list
/// of lists; those are skipped, because the image that holds them lists the
/// same methods in its own `__objc_catlist`.
package final class ObjCMethodNames: ImageFunctionTableAttachment, @unchecked Sendable {
    package struct Method: Sendable {
        package let className: String
        package let selector: String
        package let isClassMethod: Bool
    }

    package let methodsByAddress: [UInt64: Method]
    package let approximateByteCount: Int

    package static func of(_ table: ImageFunctionTable) -> ObjCMethodNames {
        table.attachment(ObjCMethodNames.self) { ObjCMethodNames(table: table) }
    }

    /// The names, when something has read them; for tests and hosts that
    /// count what an image keeps.
    package static func existing(in table: ImageFunctionTable) -> ObjCMethodNames? {
        table.existingAttachment(ObjCMethodNames.self)
    }

    private init(table: ImageFunctionTable) {
        let image = table.image
        let textRange = table.textStart ..< table.textEnd
        var methods: [UInt64: Method] = [:]
        // A class's methods share its name's storage.
        var stringByteCount = 0

        func unslidAddress(ofImplementation implementation: UInt64) -> UInt64 {
            table.unslidAddress(ofRuntime: UInt(truncatingIfNeeded: implementation) & table.memory.addressMask)
        }

        func record(_ methodList: ObjCMethodList, in listImage: MachOImage, className: String, isClassMethod: Bool) {
            guard !methodList.isListOfLists else { return }
            for method in methodList.methods(in: listImage) where method.imp != 0 {
                let address = unslidAddress(ofImplementation: method.imp)
                guard textRange.contains(address), methods[address] == nil else { continue }
                methods[address] = Method(className: className, selector: method.name, isClassMethod: isClassMethod)
                stringByteCount += ApproximateSize.of(method.name)
            }
        }

        func ownLists(of readOnlyData: ObjCClassROData64, in owner: MachOImage) -> [(MachOImage, ObjCMethodList)] {
            if let methodList = readOnlyData.methodList(in: owner) { return [(owner, methodList)] }
            guard let listOfLists = readOnlyData.methodRelativeListList(in: owner) else { return [] }
            return listOfLists.lists(in: owner).filter { $0.0.ptr == image.ptr }
        }

        for classObject in image.objc.classes64 ?? [] {
            guard let readOnlyData = ObjectiveCClassIndex.readOnlyData(of: classObject, in: image),
                  let className = readOnlyData.name(in: image)
            else { continue }
            stringByteCount += ApproximateSize.of(className)
            for (listImage, methodList) in ownLists(of: readOnlyData, in: image) {
                record(methodList, in: listImage, className: className, isClassMethod: false)
            }
            if let (metaImage, metaClass) = classObject.metaClass(in: image),
               let metaReadOnlyData = ObjectiveCClassIndex.readOnlyData(of: metaClass, in: metaImage) {
                for (listImage, methodList) in ownLists(of: metaReadOnlyData, in: metaImage) {
                    record(methodList, in: listImage, className: className, isClassMethod: true)
                }
            }
        }
        for category in (image.objc.categories64 ?? []) + (image.objc.categories2_64 ?? []) {
            guard let className = category.className(in: image), !className.isEmpty else { continue }
            stringByteCount += ApproximateSize.of(className)
            if let methodList = category.instanceMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: false)
            }
            if let methodList = category.classMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: true)
            }
        }
        self.methodsByAddress = methods
        self.approximateByteCount = stringByteCount + ApproximateSize.of(methods)
    }
}
