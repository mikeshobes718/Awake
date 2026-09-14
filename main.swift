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
        ("Keep awake 6 hours", 21600),
        ("Keep awake 8 hours", 28800),
        ("Keep awake indefinitely", nil)
    ]

    var statusRow: NSMenuItem!
    var durationItems: [NSMenuItem] = []
    var customItem: NSMenuItem!
    var stopItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var testItem: NSMenuItem?

    var assertionID: IOPMAssertionID = 0
    var hasAssertion = false
    var activeDurationIndex: Int?
    var customIsActive = false
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

        customItem = NSMenuItem(title: customMenuTitle(), action: #selector(customTime(_:)), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)

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

    func start(duration: TimeInterval?, index: Int, custom: Bool = false) {
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
            customIsActive = false
            expirationDate = nil
            refreshMenu()
            return
        }
        hasAssertion = true
        customIsActive = custom
        activeDurationIndex = custom ? nil : index
        expirationDate = duration.map { Date().addingTimeInterval($0) }
        refreshMenu()
    }

    func stopAll() {
        stopAssertion()
        activeDurationIndex = nil
        customIsActive = false
        expirationDate = nil
        refreshMenu()
    }

    @objc func customTime(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        let hours = UserDefaults.standard.object(forKey: "customHours") as? Int ?? 0
        var minutes = UserDefaults.standard.object(forKey: "customMinutes") as? Int ?? 45
        if hours == 0 && minutes == 0 { minutes = 45 }

        let accessory = CustomTimeAccessory(hours: hours, minutes: minutes)
        let alert = NSAlert()
        alert.messageText = "Custom time"
        alert.informativeText = "How long should the display stay awake?"
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Keep awake")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = accessory.hoursField

        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        guard response == .alertFirstButtonReturn else { return }

        let h = accessory.hoursValue
        let m = accessory.minutesValue
        guard h > 0 || m > 0 else { return }
        UserDefaults.standard.set(h, forKey: "customHours")
        UserDefaults.standard.set(m, forKey: "customMinutes")
        start(duration: TimeInterval(h * 3600 + m * 60), index: -2, custom: true)
    }

    func customMenuTitle() -> String {
        let h = UserDefaults.standard.object(forKey: "customHours") as? Int ?? 0
        let m = UserDefaults.standard.object(forKey: "customMinutes") as? Int ?? 45
        if h == 0 && m == 0 { return "Custom time..." }
        return "Custom time (\(formatDurationLabel(hours: h, minutes: m)))..."
    }

    func formatDurationLabel(hours: Int, minutes: Int) -> String {
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
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
                let remaining = formatRemaining(exp)
                statusRow.title = "Time left " + remaining
                statusItem.button?.title = remaining
            } else {
                statusRow.title = "Awake indefinitely"
                statusItem.button?.title = ""
            }
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
            item.state = (hasAssertion && !customIsActive && index == activeDurationIndex) ? .on : .off
        }
        customItem.title = customMenuTitle()
        customItem.state = (hasAssertion && customIsActive) ? .on : .off
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

final class CustomTimeAccessory: NSView, NSTextFieldDelegate {
    let hoursField = NSTextField()
    let minutesField = NSTextField()

    var hoursValue: Int { clamp(Int(hoursField.stringValue) ?? 0, 0, 99) }
    var minutesValue: Int { clamp(Int(minutesField.stringValue) ?? 0, 0, 59) }

    init(hours: Int, minutes: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 54))
        let hoursLabel = label("Hours")
        let minutesLabel = label("Minutes")
        style(hoursField)
        style(minutesField)
        hoursField.stringValue = String(hours)
        minutesField.stringValue = String(minutes)
        hoursField.delegate = self
        minutesField.delegate = self
        hoursLabel.frame = NSRect(x: 0, y: 32, width: 130, height: 16)
        minutesLabel.frame = NSRect(x: 150, y: 32, width: 130, height: 16)
        hoursField.frame = NSRect(x: 0, y: 4, width: 130, height: 24)
        minutesField.frame = NSRect(x: 150, y: 4, width: 130, height: 24)
        addSubview(hoursLabel)
        addSubview(minutesLabel)
        addSubview(hoursField)
        addSubview(minutesField)
    }

    required init?(coder: NSCoder) { nil }

    func controlTextDidEndEditing(_ obj: Notification) {
        hoursField.stringValue = String(hoursValue)
        minutesField.stringValue = String(minutesValue)
    }

    private func label(_ title: String) -> NSTextField {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        return t
    }

    private func style(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 13)
        field.alignment = .center
        field.placeholderString = "0"
    }

    private func clamp(_ value: Int, _ lo: Int, _ hi: Int) -> Int {
        min(hi, max(lo, value))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
let notifyDelegate = NotifyDelegate()
UNUserNotificationCenter.current().delegate = notifyDelegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
