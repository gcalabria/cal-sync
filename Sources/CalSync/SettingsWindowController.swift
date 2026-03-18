import AppKit
import EventKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var sourcePopup: NSPopUpButton!
    private var destPopup: NSPopUpButton!
    private var directionPopup: NSPopUpButton!
    private var intervalStepper: NSStepper!
    private var intervalLabel: NSTextField!
    private var showIconCheckbox: NSButton!
    private var calendars: [EKCalendar] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CalSync Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        setupUI()
        loadCalendars()
        loadSettings()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let labelWidth: CGFloat = 140
        let controlX = padding + labelWidth + 10
        let controlWidth: CGFloat = 230
        let rowHeight: CGFloat = 30
        var y: CGFloat = 260

        // Source Calendar
        let sourceLabel = makeLabel("Source Calendar:", frame: NSRect(x: padding, y: y, width: labelWidth, height: rowHeight))
        contentView.addSubview(sourceLabel)
        sourcePopup = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        contentView.addSubview(sourcePopup)

        // Destination Calendar
        y -= 40
        let destLabel = makeLabel("Destination Calendar:", frame: NSRect(x: padding, y: y, width: labelWidth, height: rowHeight))
        contentView.addSubview(destLabel)
        destPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        contentView.addSubview(destPopup)

        // Sync Direction
        y -= 40
        let dirLabel = makeLabel("Sync Direction:", frame: NSRect(x: padding, y: y, width: labelWidth, height: rowHeight))
        contentView.addSubview(dirLabel)
        directionPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: controlWidth, height: 26))
        directionPopup.addItems(withTitles: [
            SyncDirection.oneWay.displayName,
            SyncDirection.twoWay.displayName
        ])
        contentView.addSubview(directionPopup)

        // Auto-Sync Interval
        y -= 40
        let intervalTitleLabel = makeLabel("Auto-Sync Interval:", frame: NSRect(x: padding, y: y, width: labelWidth, height: rowHeight))
        contentView.addSubview(intervalTitleLabel)

        intervalStepper = NSStepper(frame: NSRect(x: controlX, y: y + 2, width: 19, height: 24))
        intervalStepper.minValue = 0
        intervalStepper.maxValue = 120
        intervalStepper.increment = 5
        intervalStepper.integerValue = 30
        intervalStepper.target = self
        intervalStepper.action = #selector(stepperChanged)
        contentView.addSubview(intervalStepper)

        intervalLabel = NSTextField(labelWithString: "30 min")
        intervalLabel.frame = NSRect(x: controlX + 28, y: y + 2, width: 100, height: rowHeight)
        contentView.addSubview(intervalLabel)

        let hint = NSTextField(labelWithString: "(0 = manual only)")
        hint.frame = NSRect(x: controlX + 100, y: y + 2, width: 130, height: rowHeight)
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(hint)

        // Show Status Bar Icon
        y -= 40
        showIconCheckbox = NSButton(checkboxWithTitle: "Show status bar icon", target: nil, action: nil)
        showIconCheckbox.frame = NSRect(x: controlX, y: y, width: controlWidth, height: rowHeight)
        contentView.addSubview(showIconCheckbox)

        // Save Button
        y -= 50
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: controlX + controlWidth - 80, y: y, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let reloadButton = NSButton(title: "Reload Calendars", target: self, action: #selector(reloadCalendars))
        reloadButton.frame = NSRect(x: padding, y: y, width: 140, height: 32)
        reloadButton.bezelStyle = .rounded
        contentView.addSubview(reloadButton)
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }

    // MARK: - Calendar Loading

    private func loadCalendars() {
        calendars = CalendarSyncService.shared.availableCalendars()
            .sorted { "\($0.source.title) - \($0.title)" < "\($1.source.title) - \($1.title)" }

        sourcePopup.removeAllItems()
        destPopup.removeAllItems()

        sourcePopup.addItem(withTitle: "— Select —")
        destPopup.addItem(withTitle: "— Select —")

        for cal in calendars {
            let title = "\(cal.source.title) → \(cal.title)"
            sourcePopup.addItem(withTitle: title)
            destPopup.addItem(withTitle: title)
        }
    }

    @objc private func reloadCalendars() {
        let currentSource = Settings.shared.sourceCalendarId
        let currentDest = Settings.shared.destinationCalendarId
        loadCalendars()
        selectCalendar(withId: currentSource, in: sourcePopup)
        selectCalendar(withId: currentDest, in: destPopup)
    }

    // MARK: - Settings Load/Save

    private func loadSettings() {
        let settings = Settings.shared
        selectCalendar(withId: settings.sourceCalendarId, in: sourcePopup)
        selectCalendar(withId: settings.destinationCalendarId, in: destPopup)

        directionPopup.selectItem(withTitle: settings.syncDirection.displayName)

        intervalStepper.integerValue = settings.syncIntervalMinutes
        updateIntervalLabel()

        showIconCheckbox.state = settings.showStatusBarIcon ? .on : .off
    }

    private func selectCalendar(withId identifier: String?, in popup: NSPopUpButton) {
        guard let id = identifier else {
            popup.selectItem(at: 0)
            return
        }
        if let index = calendars.firstIndex(where: { $0.calendarIdentifier == id }) {
            popup.selectItem(at: index + 1) // +1 for "— Select —"
        } else {
            popup.selectItem(at: 0)
        }
    }

    @objc private func save() {
        let settings = Settings.shared

        let sourceIndex = sourcePopup.indexOfSelectedItem - 1
        let destIndex = destPopup.indexOfSelectedItem - 1

        if sourceIndex >= 0 && sourceIndex < calendars.count {
            settings.sourceCalendarId = calendars[sourceIndex].calendarIdentifier
        } else {
            settings.sourceCalendarId = nil
        }

        if destIndex >= 0 && destIndex < calendars.count {
            settings.destinationCalendarId = calendars[destIndex].calendarIdentifier
        } else {
            settings.destinationCalendarId = nil
        }

        if directionPopup.titleOfSelectedItem == SyncDirection.twoWay.displayName {
            settings.syncDirection = .twoWay
        } else {
            settings.syncDirection = .oneWay
        }

        settings.syncIntervalMinutes = intervalStepper.integerValue
        settings.showStatusBarIcon = showIconCheckbox.state == .on

        window?.close()
    }

    // MARK: - Stepper

    @objc private func stepperChanged() {
        updateIntervalLabel()
    }

    private func updateIntervalLabel() {
        let val = intervalStepper.integerValue
        intervalLabel.stringValue = val == 0 ? "Disabled" : "\(val) min"
    }
}
