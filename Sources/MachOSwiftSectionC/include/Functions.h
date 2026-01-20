//
//  Function.h
//  Echo
//
//  Based on code originally created by Alejandro Alonso
//  Original Copyright (c) 2021 Alejandro Alonso
//
//  MachOSwiftSectionC
//
//  Modified by Mx-Iris on 2025/12/18.
//  Copyright (c) 2025 Mx-Iris. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#ifndef FUNCTIONS_H
#define FUNCTIONS_H

#include <stdbool.h>
#include <stddef.h>

//===----------------------------------------------------------------------===//
// Pointer Authentication
//===----------------------------------------------------------------------===//

#if defined(__arm64e__)
const void *__ptrauth_strip_asda(const void *ptr);
#endif

//===----------------------------------------------------------------------===//
// Box Functions
//===----------------------------------------------------------------------===//

// void swift_deallocBox(HeapObject *obj);
extern void swift_deallocBox(void *heapObj);

// OpaqueValue *swift_projectBox(HeapObject *obj);
extern void *swift_projectBox(void *heapObj);

// HeapObject *swift_allocEmptyBox();
extern void *swift_allocEmptyBox();

//===----------------------------------------------------------------------===//
// Object Functions
//===----------------------------------------------------------------------===//

// HeapObject *swift_allocObject(Metadata *type, size_t size, size_t alignMask);
extern void *swift_allocObject(void *type, size_t size, size_t alignMask);

// HeapObject *swift_initStackObject(HeapMetadata *metadata,
//                                   HeapObject *obj);
extern void *swift_initStackObject(void *metadata, void *obj);

// void swift_verifyEndOfLifetime(HeapObject *obj);
extern void swift_verifyEndOfLifetime(void *obj);

// void swift_deallocObject(HeapObject *obj, size_t size, size_t alignMask);
extern void swift_deallocObject(void *obj, size_t size, size_t alignMask);

// void swift_deallocUninitializedObject(HeapObject *obj, size_t size,
//                                       size_t alignMask);
extern void swift_deallocUninitializedObject(void *obj, size_t size,
                                             size_t alignMask);

// void swift_release(HeapObject *obj);
extern void swift_release(void *heapObj);

// HeapObject *swift_weakLoadStrong(WeakReference *weakRef);
extern void *swift_weakLoadStrong(void *weakRef);

//===----------------------------------------------------------------------===//
// Protocol Conformances
//===----------------------------------------------------------------------===//

// WitnessTable *swift_conformsToProtocol(Metadata *type,
//                                        ProtocolDescriptor *protocol);
extern const void *swift_conformsToProtocol(const void *type, const void *protocol);

//===----------------------------------------------------------------------===//
// Casting
//===----------------------------------------------------------------------===//

// bool swift_dynamicCast(OpaqueValue *dest, OpaqueValue *src,
//                        const Metadata *srcType, const Metadata *targetType,
//                        DynamicCastFlags flags);
extern bool swift_dynamicCast(void *dest, void *src, const void *srcType,
                              const void *targetType, size_t flags);

extern const void *swift_getTypeByMangledNameInContext(const char *typeNameStart, size_t typeNameLength, const void *context, const void *genericArgs);

extern const void *swift_getTypeByMangledNameInEnvironment(const char *typeNameStart, size_t typeNameLength, const void *environment, const void *genericArgs);

//===----------------------------------------------------------------------===//
// Obj-C Support
//===----------------------------------------------------------------------===//

#if defined(__OBJC__)
#include <objc/runtime.h>

extern Class swift_getInitializedObjCClass(Class c);

#endif // defined(__OBJC__)

#endif /* FUNCTIONS_H */
