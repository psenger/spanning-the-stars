import AppKit
import SwiftUI

@MainActor
enum InteractionSound: String {
    case activate = "Tink"
    case selection = "Pop"

    private static let sounds: [Self: NSSound] = {
        let directory = URL(filePath: "/System/Library/Sounds", directoryHint: .isDirectory)
        return Dictionary(uniqueKeysWithValues: [Self.activate, .selection].compactMap { cue in
            let file = directory.appending(path: cue.rawValue + ".aiff")
            return NSSound(contentsOf: file, byReference: false).map { (cue, $0) }
        })
    }()

    func play() {
        guard let sound = Self.sounds[self] else { return }
        if sound.isPlaying { sound.stop() }
        sound.currentTime = 0
        sound.play()
    }
}

/// Plays sound from the button action, so mouse, keyboard and accessibility activation agree.
struct GameButton<Label: View>: View {
    var role: ButtonRole? = nil
    let help: String
    var sound: InteractionSound? = .activate
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(role: role) {
            sound?.play()
            action()
        } label: {
            label()
        }
        .help(help)
    }
}

extension GameButton where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, help: String,
         sound: InteractionSound? = .activate, action: @escaping () -> Void) {
        self.init(role: role, help: help, sound: sound, action: action) { Text(title) }
    }
}
