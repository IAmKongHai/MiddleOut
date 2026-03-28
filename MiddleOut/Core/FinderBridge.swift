// FinderBridge.swift
// Executes AppleScript to retrieve the currently selected file URLs from Finder.
// Returns an empty array if Finder is not frontmost or nothing is selected.

import AppKit

enum FinderBridgeError: Error {
    case scriptFailed(String)
    case permissionDenied
}

struct FinderBridge {

    /// Get the currently selected file URLs from Finder.
    /// Returns an empty array if nothing is selected or Finder is not active.
    static func getSelection() throws -> [URL] {
        let script = """
        tell application "Finder"
            set theSelection to selection
            if theSelection is {} then
                return {}
            end if
            set thePaths to {}
            repeat with theItem in theSelection
                set end of thePaths to POSIX path of (theItem as alias)
            end repeat
            return thePaths
        end tell
        """

        let appleScript = NSAppleScript(source: script)!
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 = user denied permission
            if errorNumber == -1743 {
                throw FinderBridgeError.permissionDenied
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw FinderBridgeError.scriptFailed(message)
        }

        // Parse result: can be a single string or a list of strings
        var urls: [URL] = []
        let count = result.numberOfItems
        if count == 0 {
            // Single item or empty
            if let path = result.stringValue, !path.isEmpty {
                urls.append(URL(fileURLWithPath: path))
            }
        } else {
            for i in 1...count {
                if let item = result.atIndex(i), let path = item.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }

        return urls
    }
}
