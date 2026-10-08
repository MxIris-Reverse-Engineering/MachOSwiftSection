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
#include <stdint.h>

#include "CallAccessor.h"

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

//MetadataResponse
//swift::swift_getAssociatedTypeWitness(MetadataRequest request,
//                                      WitnessTable *wtable,
//                                      const Metadata *conformingType,
//                                      const ProtocolRequirement *reqBase,
//                                      const ProtocolRequirement *assocType)

extern const MetadataResponse swift_getAssociatedTypeWitness(size_t request, const void *wtable, const void *conformingType, const void *reqBase, const void *assocType);

//===----------------------------------------------------------------------===//
// Metadata Construction
//===----------------------------------------------------------------------===//

// MetadataResponse swift_checkMetadataState(MetadataRequest request, const Metadata *type);
extern const MetadataResponse swift_checkMetadataState(size_t request, const void *type);

// const FunctionTypeMetadata *
// swift_getFunctionTypeMetadata(FunctionTypeFlags flags, const Metadata *const *parameters,
//                               const uint32_t *parameterFlags, const Metadata *result);
extern const void *swift_getFunctionTypeMetadata(size_t flags, const void *const *parameters,
                                                 const uint32_t *parameterFlags, const void *result);

// const FunctionTypeMetadata *
// swift_getExtendedFunctionTypeMetadata(FunctionTypeFlags flags,
//                                       FunctionMetadataDifferentiabilityKind diffKind,
//                                       const Metadata *const *parameters,
//                                       const uint32_t *parameterFlags, const Metadata *result,
//                                       const Metadata *globalActor,
//                                       ExtendedFunctionTypeFlags extFlags,
//                                       const Metadata *thrownError);
// Weak: only present in newer Swift runtimes; check the symbol's address before calling.
extern const void *swift_getExtendedFunctionTypeMetadata(size_t flags, size_t diffKind,
                                                         const void *const *parameters,
                                                         const uint32_t *parameterFlags,
                                                         const void *result, const void *globalActor,
                                                         uint32_t extFlags, const void *thrownError)
    __attribute__((weak_import));

// const Metadata *swift_getMetatypeMetadata(const Metadata *instanceType);
extern const void *swift_getMetatypeMetadata(const void *instanceType);

// const ExistentialMetatypeMetadata *swift_getExistentialMetatypeMetadata(const Metadata *instanceType);
extern const void *swift_getExistentialMetatypeMetadata(const void *instanceType);

// const ExistentialTypeMetadata *
// swift_getExistentialTypeMetadata(ProtocolClassConstraint classConstraint,
//                                  const Metadata *superclassConstraint,
//                                  size_t numProtocols, const ProtocolDescriptorRef *protocols);
// The runtime sorts the protocols array in place — always pass a mutable copy.
// ProtocolClassConstraint is ABI-inverted: Class = 0, Any = 1.
extern const void *swift_getExistentialTypeMetadata(uint8_t classConstraint,
                                                    const void *superclassConstraint,
                                                    size_t numProtocols, void *protocols);

// MetadataResponse swift_getTupleTypeMetadata(MetadataRequest request, TupleTypeFlags flags,
//                                             const Metadata *const *elements, const char *labels,
//                                             const ValueWitnessTable *proposedWitnesses);
extern const MetadataResponse swift_getTupleTypeMetadata(size_t request, size_t flags,
                                                         const void *const *elements,
                                                         const char *labels,
                                                         const void *proposedWitnesses);

//===----------------------------------------------------------------------===//
// Obj-C Support
//===----------------------------------------------------------------------===//

#if defined(__OBJC__)
#include <objc/runtime.h>

extern Class swift_getInitializedObjCClass(Class c);

#endif // defined(__OBJC__)

#endif /* FUNCTIONS_H */
