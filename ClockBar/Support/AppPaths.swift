import Foundation

let appName = "ClockBar"
let appBundleIdentifier = "com.clockbar.app"
let baseURL = URL(string: "https://pro.104.com.tw")!
let holidayBaseURL = "https://cdn.jsdelivr.net/gh/ruyut/TaiwanCalendar/data/"
let launchdLabelPrefix = "com.clockbar.104-"
let notificationErrorSound = "Basso"
let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".104", isDirectory: true)
let holidayDirectory = cacheDirectory.appendingPathComponent("holidays", isDirectory: true)
let configPath = cacheDirectory.appendingPathComponent("config.json")
let logPath = cacheDirectory.appendingPathComponent("clockbar.log")
let autoPunchKillSwitchPath = cacheDirectory.appendingPathComponent("autopunch-disabled")
let autoPunchLockPath = cacheDirectory.appendingPathComponent("auto-punch.lock")
let nextPunchPath = cacheDirectory.appendingPathComponent("next-punch.json")
let sessionPath = cacheDirectory.appendingPathComponent("session.json")
let launchAgentDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
