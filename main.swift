import AppKit
import IOKit
import IOKit.pwr_mgt
import ServiceManagement
import UserNotifications

final class NotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let durations: [(String, TimeInterval?)] = [
        ("Keep awake 30 minutes", 1800),
        ("Keep awake 1 hour", 3600),
        ("Keep awake 2 hours", 7200),
        ("Keep awake 4 hours", 14400),
        ("Keep awake indefinitely", nil)
    ]

    var statusRow: NSMenuItem!
    var durationItems: [NSMenuItem] = []
    var stopItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var testItem: NSMenuItem?

    var assertionID: IOPMAssertionID = 0
    var hasAssertion = false
    var activeDurationIndex: Int?
    var expirationDate: Date?
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Awake") {
            icon.isTemplate = true
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "Awake"
        }

        statusRow = NSMenuItem(title: "Display sleep: Off", action: nil, keyEquivalent: "")
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())

        for (index, entry) in durations.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
            durationItems.append(item)
        }

        stopItem = NSMenuItem(title: "Turn off", action: #selector(stop(_:)), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        if ProcessInfo.processInfo.arguments.contains("--notify-test") {
            let item = NSMenuItem(title: "Test notification (10s)", action: #selector(testNotify(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            testItem = item
        }

        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        let quit = NSMenuItem(title: "Quit Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        refreshMenu()
        requestNotificationPermissionIfNeeded()

        let t = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func selectDuration(_ sender: NSMenuItem) {
        start(duration: durations[sender.tag].1, index: sender.tag)
    }

    @objc func stop(_ sender: NSMenuItem) {
        stopAll()
    }

    func start(duration: TimeInterval?, index: Int) {
        stopAssertion()
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(255),
            "Awake" as CFString,
            &assertionID
        )
        guard result == 0 else {
            hasAssertion = false
            activeDurationIndex = nil
            expirationDate = nil
            refreshMenu()
            return
        }
        hasAssertion = true
        activeDurationIndex = index
        expirationDate = duration.map { Date().addingTimeInterval($0) }
        refreshMenu()
    }

    func stopAll() {
        stopAssertion()
        activeDurationIndex = nil
        expirationDate = nil
        refreshMenu()
    }

    func stopAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
    }

    @objc func tick() {
        if hasAssertion, let exp = expirationDate, Date() >= exp {
            stopAll()
            sendTimeUpNotification()
            return
        }
        updateStatusText()
    }

    func sendTimeUpNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Awake"
        content.body = "Time's up. Your Mac can sleep normally again."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "awake-timeup-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc func testNotify(_ sender: NSMenuItem) {
        start(duration: 10, index: -1)
    }

    func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func updateStatusText() {
        if hasAssertion {
            if let exp = expirationDate {
                statusRow.title = "Awake for " + formatRemaining(exp)
            } else {
                statusRow.title = "Awake indefinitely"
            }
            statusItem.button?.title = expirationDate.map { formatRemaining($0) } ?? ""
        } else {
            statusRow.title = "Display sleep: Off"
            statusItem.button?.title = ""
        }
    }

    func formatRemaining(_ date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSinceNow.rounded()))
        return String(format: "%d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }

    func refreshMenu() {
        for (index, item) in durationItems.enumerated() {
            item.state = (hasAssertion && index == activeDurationIndex) ? .on : .off
        }
        stopItem.isEnabled = hasAssertion
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        updateStatusText()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {}
        refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAssertion()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
let notifyDelegate = NotifyDelegate()
UNUserNotificationCenter.current().delegate = notifyDelegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
