// SoundPlayer.swift
// Plays completion and error sounds.
// Uses bundled custom sounds. Falls back to system sounds if custom not found.

import AppKit

struct SoundPlayer {

    /// Play the completion chime (after successful processing)
    static func playComplete() {
        if let sound = NSSound(named: "complete") {
            sound.play()
        } else {
            // Fallback to system sound
            NSSound.beep()
        }
    }

    /// Play an error sound (when no files selected or all skipped)
    static func playError() {
        if let sound = NSSound(named: "error") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
