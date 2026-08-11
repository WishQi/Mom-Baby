//
//  Item.swift
//  Mom-Baby
//
//  Created by Maoqi on 2026/8/11.
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
