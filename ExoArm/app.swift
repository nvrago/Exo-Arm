// PitcherRehabApp.swift
// App entry point.
//
// Xcode setup:
// 1. New > macOS > App (SwiftUI, Swift)
// 2. Product name: PitcherRehab
// 3. Info.plist: add "Privacy - Bluetooth Always Usage Description"
// 4. Signing & Capabilities: enable "App Sandbox" > "Bluetooth"
// 5. Drop all .swift files into the project navigator
//
// File layout:
// PitcherRehabApp.swift
// BLE/BLEManager.swift
// BLE/BLEConstants.swift
// Model/SensorFrame.swift
// Model/KinematicsEngine.swift
// Model/SessionRecorder.swift
// ViewModel/SessionViewModel.swift

import SwiftUI

@main
struct PitcherRehabApp: App {
    @StateObject private var session = SessionViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(session)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}