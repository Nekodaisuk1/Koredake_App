//
//  KoredakeApp.swift
//  Koredake
//
//  Created by 丹那伊織 on 2025/11/07.
//

import SwiftUI

@main
struct KoredakeApp: App {
    init() {
        GoogleServicesConfigurator.shared.configureIfNeeded()
        Notifier.requestAuth()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
