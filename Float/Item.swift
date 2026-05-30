//
//  Item.swift
//  Float
//
//  Created by SUROJIT PAUL on 29/05/26.
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
