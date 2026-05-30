//
//  Item.swift
//  DmdApp
//
//  Created by Michał Wołtosz on 30/05/2026.
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
