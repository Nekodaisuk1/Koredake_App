//
//  WeatherIconView.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI

// MARK: - Weather Icon View

struct WeatherIconView: View {
    let weather: WxFeature
    let size: CGFloat
    
    var body: some View {
        let icon = weatherIcon(for: weather)
        Image(systemName: icon.systemName)
            .font(.system(size: size))
            .foregroundColor(.white)
    }
}
