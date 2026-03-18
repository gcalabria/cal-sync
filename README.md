# CalSync

A lightweight macOS menu bar app that syncs calendar events between two calendars connected to your Mac (e.g., Gmail ↔ Microsoft). It uses Apple's EventKit framework, so any calendar visible in the macOS Calendar app can be used — no API keys or third-party services required.

## Requirements

- macOS 14.0+
- Swift 5.9+
- Both calendars must be added to macOS via **System Settings → Internet Accounts**

## Build

```bash
# Debug build
swift build

# Release build + .app bundle
./bundle.sh
```

The bundle script compiles a release build and packages it into `build/CalSync.app` with the proper Info.plist (which hides the app from the Dock).

### Install

```bash
cp -r build/CalSync.app /Applications/
```

## Usage

### First Launch

1. Run the app:
   ```bash
   open build/CalSync.app
   ```
2. A **calendar icon** (🕐) appears in the menu bar — the app has no Dock icon.
3. macOS will prompt you to grant **Calendar access**. Allow it.

### Configure

1. Click the menu bar icon → **Settings…**
2. **Source Calendar** — the calendar to read events from (e.g., your Gmail calendar).
3. **Destination Calendar** — the calendar to copy events to (e.g., your Microsoft/Outlook calendar).
4. **Sync Direction:**
   - *One-way (A → B)* — events flow from source to destination only.
   - *Two-way (A ↔ B)* — events sync in both directions.
5. **Auto-Sync Interval** — how often the app syncs automatically, in minutes (default: 30, set to 0 to disable).
6. Click **Save**.

### Sync

- **Manual:** Click the menu bar icon → **Sync Now**.
- **Automatic:** Runs on the configured interval in the background.

The menu bar icon changes while a sync is in progress. The "Last synced" timestamp updates after each successful sync.

### Launch at Login

Click the menu bar icon → **Launch at Login** to toggle starting CalSync automatically when you log in.

### Quit

Click the menu bar icon → **Quit CalSync**.

## What Gets Synced

| Field | Synced |
|---|---|
| Title | ✅ |
| Start / End time | ✅ |
| All-day flag | ✅ |
| Location | ✅ |
| Structured location | ✅ |
| Notes | ✅ |
| URL | ✅ |
| Availability | ✅ |
| Alarms / Reminders | ✅ |
| Recurrence rules | ✅ |
| Attendees | ⚠️ Appended as text in notes (read-only in EventKit) |

## How It Works

- Events are fetched from the source calendar for the next ~4 years (EventKit's maximum predicate range).
- Each synced event is tracked by its `calendarItemExternalIdentifier` in a local state file at `~/Library/Application Support/CalSync/sync-state.json`.
- **New events** in the source are created in the destination.
- **Modified events** (source changed since last sync) are updated in the destination.
- **Deleted events** (no longer in the source) are removed from the destination.
- **Deduplication:** before creating, the app checks for existing events with the same title and start time (±1 minute) to avoid duplicates.
- **Two-way sync** runs the same logic in both directions, skipping events that were created by sync to prevent loops.

## Files

| Path | Purpose |
|---|---|
| `Sources/CalSync/main.swift` | App entry point |
| `Sources/CalSync/AppDelegate.swift` | Menu bar UI, timer, window management |
| `Sources/CalSync/CalendarSyncService.swift` | EventKit sync engine |
| `Sources/CalSync/Settings.swift` | UserDefaults-backed preferences |
| `Sources/CalSync/SyncState.swift` | JSON persistence for event ID mappings |
| `Sources/CalSync/SettingsWindowController.swift` | Settings window UI |
| `Sources/CalSync/Info.plist` | App metadata (LSUIElement, permissions) |
| `bundle.sh` | Packages the binary into a .app bundle |
