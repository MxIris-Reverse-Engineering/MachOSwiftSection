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
        let textRange = table.textStart ..< table.textEnd
        var methods: [UInt64: Method] = [:]
        // A class's methods share its name's storage.
        var stringByteCount = 0

        func record(implementationAt address: UInt64, selector: String, className: String, isClassMethod: Bool) {
            guard textRange.contains(address), methods[address] == nil else { return }
            methods[address] = Method(className: className, selector: selector, isClassMethod: isClassMethod)
            stringByteCount += ApproximateSize.of(selector)
        }
        func countClassName(_ className: String) {
            stringByteCount += ApproximateSize.of(className)
        }

        // MachOObjCSection reads method lists through an API per kind of
        // reader; what each method's `imp` holds differs with it.
        if let image = table.image.reader.asMachOImage {
            Self.readMethods(in: image, table: table, countingClassName: countClassName, recordMethod: record)
        } else if let file = table.image.reader.asMachOFile {
            Self.readMethods(in: file, image: table.image, countingClassName: countClassName, recordMethod: record)
        }
        self.methodsByAddress = methods
        self.approximateByteCount = stringByteCount + ApproximateSize.of(methods)
    }

    private typealias Record = (_ address: UInt64, _ selector: String, _ className: String, _ isClassMethod: Bool) -> Void

    /// The methods of an image in this process: a method's `imp` is its
    /// runtime address, and a class the runtime has realized is read
    /// through its read-write data.
    private static func readMethods(in image: MachOImage, table: ImageFunctionTable, countingClassName: (String) -> Void, recordMethod: Record) {
        func record(_ methodList: ObjCMethodList, in listImage: MachOImage, className: String, isClassMethod: Bool) {
            guard !methodList.isListOfLists else { return }
            for method in methodList.methods(in: listImage) where method.imp != 0 {
                let address = table.unslidAddress(ofRuntime: UInt(truncatingIfNeeded: method.imp) & table.memory.addressMask)
                recordMethod(address, method.name, className, isClassMethod)
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
            countingClassName(className)
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
            countingClassName(className)
            if let methodList = category.instanceMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: false)
            }
            if let methodList = category.classMethodList(in: image) {
                record(methodList, in: image, className: className, isClassMethod: true)
            }
        }
    }

    /// The methods of an image read from a file: a method's `imp` is an
    /// offset in the reader's accounting, and no class is realized.
    private static func readMethods(in file: MachOFile, image codeImage: CodeImage, countingClassName: (String) -> Void, recordMethod: Record) {
        func record(_ methodList: ObjCMethodList, in listFile: MachOFile, className: String, isClassMethod: Bool) {
            guard !methodList.isListOfLists else { return }
            for method in methodList.methods(in: listFile) ?? [] where method.imp != 0 {
                guard let address = codeImage.unslidAddress(ofReaderOffset: Int(truncatingIfNeeded: method.imp)) else { continue }
                recordMethod(address, method.name, className, isClassMethod)
            }
        }

        func ownLists(of readOnlyData: ObjCClassROData64, in owner: MachOFile) -> [(MachOFile, ObjCMethodList)] {
            if let methodList = readOnlyData.methodList(in: owner) { return [(owner, methodList)] }
            guard let listOfLists = readOnlyData.methodRelativeListList(in: owner) else { return [] }
            return listOfLists.lists(in: owner).filter { $0.0.imagePath == file.imagePath }
        }

        for classObject in file.objc.classes64 ?? [] {
            guard let readOnlyData = classObject.classROData(in: file),
                  let className = readOnlyData.name(in: file)
            else { continue }
            countingClassName(className)
            for (listFile, methodList) in ownLists(of: readOnlyData, in: file) {
                record(methodList, in: listFile, className: className, isClassMethod: false)
            }
            if let (metaFile, metaClass) = classObject.metaClass(in: file),
               let metaReadOnlyData = metaClass.classROData(in: metaFile) {
                for (listFile, methodList) in ownLists(of: metaReadOnlyData, in: metaFile) {
                    record(methodList, in: listFile, className: className, isClassMethod: true)
                }
            }
        }
        for category in (file.objc.categories64 ?? []) + (file.objc.categories2_64 ?? []) {
            guard let className = category.className(in: file), !className.isEmpty else { continue }
            countingClassName(className)
            if let methodList = category.instanceMethodList(in: file) {
                record(methodList, in: file, className: className, isClassMethod: false)
            }
            if let methodList = category.classMethodList(in: file) {
                record(methodList, in: file, className: className, isClassMethod: true)
            }
        }
    }
}
