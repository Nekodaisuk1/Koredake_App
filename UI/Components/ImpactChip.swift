//
//  ImpactChip.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI

struct ImpactChip: View {
    let impact: Impact
    
    var body: some View {
        Text(badgeText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor.opacity(0.15))
            .foregroundColor(foregroundColor)
            .cornerRadius(6)
            .font(.caption)
    }
    
    private var badgeText: String {
        ["低", "中", "高"][impact.rawValue]
    }
    
    private var foregroundColor: Color {
        [.green, .orange, .red][impact.rawValue]
    }
    
    private var backgroundColor: Color {
        foregroundColor
    }
}

