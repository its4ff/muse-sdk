//
//  MuseApp.swift
//  muse
//
//  Voice memo app powered by smart ring
//

import SwiftUI
import SwiftData

@main
struct MuseApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: Muse.self)
    }
}
