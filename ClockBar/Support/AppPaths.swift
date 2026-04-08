import Foundation

let baseURL = URL(string: "https://pro.104.com.tw")!
let cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".104", isDirectory: true)
let holidayDirectory = cacheDirectory.appendingPathComponent("holidays", isDirectory: true)
let configPath = cacheDirectory.appendingPathComponent("config.json")
let autoPunchLogPath = cacheDirectory.appendingPathComponent("auto-punch.log")
let autoPunchKillSwitchPath = cacheDirectory.appendingPathComponent("autopunch-disabled")
let nextPunchPath = cacheDirectory.appendingPathComponent("next-punch.json")
let sessionPath = cacheDirectory.appendingPathComponent("session.json")
let launchAgentDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
