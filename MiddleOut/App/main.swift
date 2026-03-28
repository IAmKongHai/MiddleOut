// main.swift
// MiddleOut - App entry point
// Uses NSApplication directly for full AppKit lifecycle control.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
