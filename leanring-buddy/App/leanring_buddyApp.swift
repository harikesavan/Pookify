//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with companion voice controls.
//

import ServiceManagement
import SwiftUI
import Sparkle

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private let companionManager = CompanionManager()
    private let usageTracker = UsageTracker()
    private var sparkleUpdaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🎯 Clicky: Starting...")
        print("🎯 Clicky: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        ClickyAnalytics.configure()
        ClickyAnalytics.trackAppOpened()

        companionManager.usageTracker = usageTracker

        menuBarPanelManager = MenuBarPanelManager(
            companionManager: companionManager,
            usageTracker: usageTracker
        )
        companionManager.start()
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }
        registerAsLoginItemIfNeeded()
        // startSparkleUpdater()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pookify" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems else { continue }

            let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
                item.value.map { (item.name, $0) }
            })

            guard let setupToken = params["token"] else {
                print("⚠️ Pookify: Missing token in pookify:// URL")
                continue
            }

            Task {
                await exchangeSetupToken(setupToken)
            }
        }
    }

    private func exchangeSetupToken(_ token: String) async {
        let workerBaseURL = "http://localhost:8787"
        let url = URL(string: "\(workerBaseURL)/exchange-token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ Pookify: Token exchange failed (\(statusCode)): \(body)")
                return
            }

            let config = try JSONDecoder().decode(CompanyConfig.self, from: data)
            await MainActor.run {
                CompanyConfigManager.saveConfig(config)
                companionManager.reloadCompanyConfig()
                print("📋 Pookify: Configured for \(config.company_name) via setup token")
            }
        } catch {
            print("⚠️ Pookify: Token exchange error: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        companionManager.stop()
    }

    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                print("🎯 Clicky: Registered as login item")
            } catch {
                print("⚠️ Clicky: Failed to register as login item: \(error)")
            }
        }
    }

    private func startSparkleUpdater() {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.sparkleUpdaterController = updaterController

        do {
            try updaterController.updater.start()
        } catch {
            print("⚠️ Clicky: Sparkle updater failed to start: \(error)")
        }
    }
}
