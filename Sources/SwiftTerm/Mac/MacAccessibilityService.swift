//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 3/5/20.
//

import Foundation

class AccessibilityService {
    func invalidate ()
    {

    }
}

/// Snapshot of the selection state last announced to accessibility clients, so
/// `.selectedTextChanged` is only posted when the selection actually changed
/// (streaming output alone must not re-announce an unchanged selection).
struct AXSelectionSignature: Equatable {
    let active: Bool
    let start: Position
    let end: Position
}
