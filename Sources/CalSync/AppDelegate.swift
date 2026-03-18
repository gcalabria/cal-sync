import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var lastSyncedMenuItem: NSMenuItem!
    private var syncNowMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var syncTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private let syncService = CalendarSyncService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        scheduleSyncTimer()
        syncService.requestAccess { [weak self] granted in
            if !granted {
                DispatchQueue.main.async {
                    self?.showPermissionAlert()
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Settings.didChangeNotification,
            object: nil
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "calendar.badge.clock",
                accessibilityDescription: "CalSync"
            )
        }

        let menu = NSMenu()

        syncNowMenuItem = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "s")
        syncNowMenuItem.target = self
        menu.addItem(syncNowMenuItem)

        lastSyncedMenuItem = NSMenuItem(title: "Last synced: Never", action: nil, keyEquivalent: "")
        lastSyncedMenuItem.isEnabled = false
        menu.addItem(lastSyncedMenuItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let viewLogItem = NSMenuItem(title: "View Log", action: #selector(viewLog), keyEquivalent: "l")
        viewLogItem.target = self
        menu.addItem(viewLogItem)

        menu.addItem(NSMenuItem.separator())

        launchAtLoginMenuItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginState()
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit CalSync", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Sync

    @objc private func syncNow() {
        guard Settings.shared.sourceCalendarId != nil,
              Settings.shared.destinationCalendarId != nil else {
            showAlert(title: "Not Configured", message: "Please select source and destination calendars in Settings.")
            return
        }

        setSyncingState(true)

        syncService.sync { [weak self] result in
            DispatchQueue.main.async {
                self?.setSyncingState(false)
                switch result {
                case .success(let stats):
                    self?.updateLastSynced()
                    if stats.errors > 0 {
                        let details = stats.errorMessages.prefix(5).joined(separator: "\n• ")
                        self?.showAlert(
                            title: "Sync Completed with Errors",
                            message: "Created: \(stats.created), Updated: \(stats.updated), Deleted: \(stats.deleted), Errors: \(stats.errors)\n\n• \(details)\n\nSee View Log for full details."
                        )
                    }
                case .failure(let error):
                    self?.showAlert(title: "Sync Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func setSyncingState(_ syncing: Bool) {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: syncing ? "arrow.triangle.2.circlepath" : "calendar.badge.clock",
                accessibilityDescription: "CalSync"
            )
        }
        syncNowMenuItem.title = syncing ? "Syncing…" : "Sync Now"
        syncNowMenuItem.isEnabled = !syncing
    }

    private func updateLastSynced() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        lastSyncedMenuItem.title = "Last synced: \(formatter.string(from: Date()))"
    }

    // MARK: - Timer

    func scheduleSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil

        let interval = Settings.shared.syncIntervalMinutes
        guard interval > 0 else { return }

        syncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval * 60), repeats: true) { [weak self] _ in
            self?.syncNow()
        }
    }

    @objc private func settingsDidChange() {
        scheduleSyncTimer()
        statusItem.isVisible = Settings.shared.showStatusBarIcon
    }

    // MARK: - Settings Window

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                showAlert(title: "Launch at Login", message: "Could not update login item: \(error.localizedDescription)")
            }
            updateLaunchAtLoginState()
        }
    }

    private func updateLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginMenuItem.isHidden = true
        }
    }

    // MARK: - Alerts

    private func showPermissionAlert() {
        showAlert(
            title: "Calendar Access Required",
            message: "CalSync needs access to your calendars. Please grant permission in System Settings > Privacy & Security > Calendars."
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - View Log

    @objc private func viewLog() {
        NSWorkspace.shared.open(Logger.shared.logFileURL)
    }

    // MARK: - Quit

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTimer?.invalidate()
    }

    // MARK: - App Reopen

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When the user launches the app again while it's already running, show the Settings window.
        // This is especially useful if the status bar icon is hidden.
        openSettings()
        return true
    }
}
