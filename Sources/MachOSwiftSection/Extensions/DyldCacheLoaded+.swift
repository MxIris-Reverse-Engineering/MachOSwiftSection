//
//  DyldCacheLoaded.swift
//  MachOObjCSection
//
//  Created by p-x9 on 2024/11/02
//  
//

import MachOKit

#if !canImport(Darwin)
extension DyldCacheLoaded {
    // FIXME: fallback for linux
    public static var current: DyldCacheLoaded? {
        return nil
    }
}
#endif
