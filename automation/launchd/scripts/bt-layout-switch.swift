import Foundation
import IOBluetooth
import Carbon
import AppKit

// MARK: - Config

struct Config {
    let keyboardMAC: String
    let customLayout: String
    let defaultLayout: String
}

func loadConfig(from path: String) -> Config? {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("Config file not found: \(path)\n", stderr)
        return nil
    }
    var values: [String: String] = [:]
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        let parts = trimmed.components(separatedBy: "=")
        guard parts.count >= 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let val = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .init(charactersIn: " \""))
        values[key] = val
    }
    guard let mac = values["KEYBOARD_MAC"], !mac.isEmpty else {
        fputs("KEYBOARD_MAC is not set in config\n", stderr); return nil
    }
    guard let custom = values["CUSTOM_LAYOUT"], !custom.isEmpty else {
        fputs("CUSTOM_LAYOUT is not set in config\n", stderr); return nil
    }
    guard let def = values["DEFAULT_LAYOUT"], !def.isEmpty else {
        fputs("DEFAULT_LAYOUT is not set in config\n", stderr); return nil
    }
    return Config(keyboardMAC: mac, customLayout: custom, defaultLayout: def)
}

// MARK: - Logging

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] \(msg)")
    fflush(stdout)
}

// MARK: - TIS helpers

func findSource(id: String, includeAll: Bool = false) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
    return (TISCreateInputSourceList(filter, includeAll)?.takeRetainedValue() as? [TISInputSource])?.first
}

@discardableResult func enableSource(id: String) -> Bool {
    guard let src = findSource(id: id, includeAll: true) else {
        log("enable: \(id) not found")
        return false
    }
    let err = TISEnableInputSource(src)
    if err != noErr { log("enable err=\(err) for \(id)"); return false }
    return true
}

@discardableResult func disableSource(id: String) -> Bool {
    guard let src = findSource(id: id) else {
        return true
    }
    let err = TISDisableInputSource(src)
    if err != noErr { log("disable err=\(err) for \(id)"); return false }
    return true
}

func selectSource(id: String) {
    guard let src = findSource(id: id) else {
        log("select: \(id) not in enabled list")
        return
    }
    let err = TISSelectInputSource(src)
    if err == noErr { log("selected: \(id)") }
    else { log("select err=\(err) for \(id)") }
}

func waitForSource(id: String, timeout: Double = 30.0) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if findSource(id: id) != nil { return true }
        Thread.sleep(forTimeInterval: 0.5)
    }
    return false
}

// MARK: - One-shot activation (runs as child process, exits immediately)

func runActivateKeyboard(cfg: Config) -> Int32 {
    enableSource(id: "com.apple.keylayout.ABC")
    enableSource(id: cfg.customLayout)

    if !waitForSource(id: cfg.customLayout) {
        log("Ukulele not available after 30s — approve the keyboard layout dialog")
        return 1
    }

    disableSource(id: cfg.defaultLayout)
    selectSource(id: cfg.customLayout)
    log("activated: ABC + \(cfg.customLayout)")
    return 0
}

func runActivateBuiltIn(cfg: Config) -> Int32 {
    enableSource(id: "com.apple.keylayout.ABC")
    enableSource(id: cfg.defaultLayout)

    if !waitForSource(id: cfg.defaultLayout, timeout: 5.0) {
        log("\(cfg.defaultLayout) not available")
        return 1
    }

    disableSource(id: cfg.customLayout)
    selectSource(id: cfg.defaultLayout)
    log("activated: ABC + \(cfg.defaultLayout)")
    return 0
}

// MARK: - Daemon spawns child process for activation

func spawnActivation(binary: String, flag: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: binary)
    p.arguments = [flag]
    p.environment = ProcessInfo.processInfo.environment
    do {
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            log("activation child exited with \(p.terminationStatus)")
        }
    } catch {
        log("failed to spawn activation: \(error)")
    }
}

// MARK: - Discovery helpers

func listPairedDevices() {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        fputs("Could not list devices (check Bluetooth permission)\n", stderr)
        return
    }
    if devices.isEmpty { print("No paired devices"); return }
    print("Paired Bluetooth devices:")
    for d in devices {
        print("  \(d.addressString ?? "?")  [\(d.isConnected() ? "connected" : "not connected")]  \(d.name ?? "?")")
    }
}

func listLayouts() {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
    print("Enabled input sources:")
    for src in list {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        print("  \(Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)")
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
let binary = args[0]
let configPath: String = {
    if let env = ProcessInfo.processInfo.environment["BT_LAYOUT_CONF"] { return env }
    let base = URL(fileURLWithPath: binary).deletingLastPathComponent().path
    return base + "/../config/bt-layout.conf"
}()

if args.count > 1 {
    switch args[1] {
    case "--list-devices":  listPairedDevices(); exit(0)
    case "--list-layouts":  listLayouts(); exit(0)
    case "--request-accessibility":
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        print(trusted ? "Accessibility: already granted" : "Accessibility: dialog shown — approve, then restart daemon")
        exit(0)

    case "--activate-keyboard":
        guard let cfg = loadConfig(from: configPath) else { exit(1) }
        exit(runActivateKeyboard(cfg: cfg))

    case "--activate-builtin":
        guard let cfg = loadConfig(from: configPath) else { exit(1) }
        exit(runActivateBuiltIn(cfg: cfg))

    default:
        print("Usage: bt-layout-switch [--list-devices | --list-layouts | --request-accessibility]")
        exit(1)
    }
}

// MARK: - Daemon mode (no flags)

guard let cfg = loadConfig(from: configPath) else { exit(1) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

Thread.detachNewThread {
    log("Started. Watching: \(cfg.keyboardMAC)")
    log("  connect    → \(cfg.customLayout)")
    log("  disconnect → \(cfg.defaultLayout)")

    var lastConnected: Bool? = nil
    while true {
        if let device = IOBluetoothDevice(addressString: cfg.keyboardMAC) {
            let connected = device.isConnected()
            if connected != lastConnected {
                lastConnected = connected
                let flag = connected ? "--activate-keyboard" : "--activate-builtin"
                log("BT \(connected ? "connected" : "disconnected") → spawning \(flag)")
                spawnActivation(binary: binary, flag: flag)
            }
        }
        Thread.sleep(forTimeInterval: 3.0)
    }
}

app.run()
