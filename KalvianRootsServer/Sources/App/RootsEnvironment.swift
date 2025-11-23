//
//  RootsEnvironment.swift
//  KalvianRootsServer
//
//  Created by Michael Bendio on 11/21/25.
//

import Vapor
import Foundation

struct RootsEnvironment {
    let rootsPath: String
}

extension Application {
    struct RootsKey: StorageKey {
        typealias Value = RootsEnvironment
    }

    var roots: RootsEnvironment? {
        get { storage[RootsKey.self] }
        set { storage[RootsKey.self] = newValue }
    }
}
