//
//  DragonApp.swift
//  Dragon
//
//  Created by HH on 8/6/2026.
//

import SwiftUI

@main
struct DragonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(dataSource: DragonDataSourceFactory.defaultDataSource)
        }
    }
}
