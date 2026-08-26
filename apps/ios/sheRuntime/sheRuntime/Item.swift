//
//  Item.swift
//  sheRuntime
//
//  Created by ari on 2026/8/27.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
