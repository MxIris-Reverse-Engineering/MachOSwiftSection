//
//  CallAccessor.c
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

#include "CallAccessor.h"

#if defined(__arm64e__)
#include <ptrauth.h>
#endif

#define SWIFTCC __attribute__((swiftcall))

const MetadataResponse swift_section_callAccessor0(const void *ptr, size_t request) {
#if defined(__arm64e__)
  ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
  
  typedef SWIFTCC MetadataResponse(MetadataAccess)(size_t);
  
  return ((MetadataAccess *)ptr)(request);
}

const MetadataResponse swift_section_callAccessor1(const void *ptr, size_t request,
                                          const void *arg0) {
#if defined(__arm64e__)
  ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
  
  typedef SWIFTCC MetadataResponse(MetadataAccess)(size_t, const void*);
  
  return ((MetadataAccess *)ptr)(request, arg0);
}

const MetadataResponse swift_section_callAccessor2(const void *ptr, size_t request,
                                          const void *arg0, const void *arg1) {
#if defined(__arm64e__)
  ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
  
  typedef SWIFTCC MetadataResponse(MetadataAccess)(size_t, const void*,
                                                   const void*);
  
  return ((MetadataAccess *)ptr)(request, arg0, arg1);
}

const MetadataResponse swift_section_callAccessor3(const void *ptr, size_t request,
                                          const void *arg0, const void *arg1,
                                          const void *arg2) {
#if defined(__arm64e__)
  ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
  
  typedef SWIFTCC MetadataResponse(MetadataAccess)(size_t, const void*,
                                                   const void*, const void*);
  
  return ((MetadataAccess *)ptr)(request, arg0, arg1, arg2);
}

const MetadataResponse swift_section_callAccessor(const void *ptr, size_t request,
                                         const void *args) {
#if defined(__arm64e__)
  ptr = ptrauth_sign_unauthenticated(ptr, ptrauth_key_function_pointer, 0);
#endif
  
  typedef SWIFTCC MetadataResponse(MetadataAccess)(size_t, const void*);
  
  return ((MetadataAccess *)ptr)(request, args);
}
