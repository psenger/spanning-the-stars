import SwiftUI
import StarsCore

// Ported from saltmarsh-isles (App/Views/SavedGamesSheets.swift): same flows, this game's wording.

private enum SaveText {
    static let saveTitle = "Save Game", loadTitle = "Load Game", name = "Name"
    static let save = "Save", load = "Load", replace = "Replace", delete = "Delete", cancel = "Cancel"
    static let noSaves = "No saved games yet."
    static let full = "All 5 saves are used. Click one to replace it, or delete one to make room."
    static let clickToReplace = "Or click a save to replace it."
    static let loadWarning = "This replaces the Charter in progress.", replaceWarning = "The saved game will be overwritten."
    static let deleteWarning = "This cannot be undone."
    static func replacePrompt(_ name: String) -> String { "Replace \"\(name)\"?" }
    static func deletePrompt(_ name: String) -> String { "Delete \"\(name)\"?" }
    static func loadPrompt(_ name: String) -> String { "Load \"\(name)\"?" }
}

private func dated(_ save: SavedGameSummary) -> String {
    save.savedAt.formatted(date: .abbreviated, time: .shortened)
}

/// One save in a list: its name, when it was saved and its Houses.
private struct SaveRow: View {
    let save: SavedGameSummary

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(save.name).foregroundStyle(.primary)
                Text(dated(save)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: -6) {
                ForEach(save.houses, id: \.self) { ArtImage(.house($0)).frame(width: 20, height: 20) }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A save row with a trash can that asks before deleting.
private struct SaveList: View {
    let saves: [SavedGameSummary]
    var disabled = false
    let pick: (SavedGameSummary) -> Void
    let delete: (SavedGameSummary) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(saves) { save in
                    HStack {
                        GameButton(help: "Select \(save.name)", sound: .selection) { pick(save) } label: { SaveRow(save: save).padding(.vertical, 6) }
                            .buttonStyle(.plain)
                            .disabled(disabled)
                        GameButton(help: "Delete the saved game \(save.name)") { delete(save) } label: {
                            Image(systemName: "trash").frame(width: 32, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("\(SaveText.delete) \(save.name)")
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 300)
    }
}

/// Asks before deleting a save, shared by both sheets.
private struct DeleteConfirmation: ViewModifier {
    @Binding var deleting: SavedGameSummary?
    let delete: (SavedGameSummary) -> Void

    func body(content: Content) -> some View {
        content.alert(deleting.map { SaveText.deletePrompt($0.name) } ?? "",
                      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                      presenting: deleting) { target in
            Button(SaveText.delete, role: .destructive) {
                InteractionSound.activate.play()
                delete(target)
            }
            Button(SaveText.cancel, role: .cancel) { InteractionSound.activate.play() }
        } message: { _ in
            Text(SaveText.deleteWarning)
        }
    }
}

/// Names and keeps a copy of the current Charter. With all saves used, the only way to save is to pick one to replace.
struct SaveGameSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saves: [SavedGameSummary] = []
    @State private var replacing: SavedGameSummary?
    @State private var deleting: SavedGameSummary?
    @State private var problem: String?

    private var full: Bool { saves.count >= SaveLimit.maxSaves }
    private var nameIsBlank: Bool { SaveLimit.clipped(name).isEmpty }

    private func save(replacing target: UUID? = nil) {
        do {
            try model.saveGame(named: name, replacing: target)
            dismiss()
        } catch {
            problem = "That game could not be saved. \(error.localizedDescription)"
        }
    }

    private func delete(_ save: SavedGameSummary) {
        do {
            try model.deleteSavedGame(id: save.id)
            saves = model.savedGames()
            problem = nil
        } catch {
            problem = "\"\(save.name)\" could not be deleted. \(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SaveText.saveTitle).font(.title2.bold())
            TextField(SaveText.name, text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { _, typed in
                    if typed.count > SaveLimit.maxNameLength { name = String(typed.prefix(SaveLimit.maxNameLength)) }
                }
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if !saves.isEmpty {
                Text(full ? SaveText.full : SaveText.clickToReplace).font(.callout).foregroundStyle(.secondary)
                SaveList(saves: saves, disabled: nameIsBlank, pick: { replacing = $0 }, delete: { deleting = $0 })
            }
            HStack {
                GameButton(SaveText.cancel, help: "Close without saving") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                GameButton(SaveText.save, help: "Save a named copy of this game") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(full || nameIsBlank)
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 440)
        .onAppear {
            name = model.suggestedSaveName
            saves = model.savedGames()
        }
        .alert(replacing.map { SaveText.replacePrompt($0.name) } ?? "",
               isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
               presenting: replacing) { target in
            Button(SaveText.replace, role: .destructive) {
                InteractionSound.activate.play()
                save(replacing: target.id)
            }
            Button(SaveText.cancel, role: .cancel) { InteractionSound.activate.play() }
        } message: { _ in
            Text(SaveText.replaceWarning)
        }
        .modifier(DeleteConfirmation(deleting: $deleting, delete: delete))
    }
}

/// Lists the saves. With a Charter in progress, picking one asks first, because loading replaces it.
/// A loaded game opens on its hand-off screen.
struct LoadGameSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var saves: [SavedGameSummary] = []
    @State private var loading: SavedGameSummary?
    @State private var deleting: SavedGameSummary?
    @State private var problem: String?

    private func load(_ save: SavedGameSummary) {
        do {
            try model.loadGame(id: save.id)
            dismiss()
        } catch {
            problem = "\"\(save.name)\" could not be loaded. \(error.localizedDescription)"
        }
    }

    private func pick(_ save: SavedGameSummary) {
        if model.gameInProgress { loading = save } else { load(save) }
    }

    private func delete(_ save: SavedGameSummary) {
        do {
            try model.deleteSavedGame(id: save.id)
            saves = model.savedGames()
            problem = nil
        } catch {
            problem = "\"\(save.name)\" could not be deleted. \(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SaveText.loadTitle).font(.title2.bold())
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if saves.isEmpty {
                Text(SaveText.noSaves).foregroundStyle(.secondary)
            } else {
                SaveList(saves: saves, pick: pick, delete: { deleting = $0 })
            }
            HStack {
                Spacer()
                GameButton(SaveText.cancel, help: "Close without loading a game") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 440)
        .onAppear { saves = model.savedGames() }
        .alert(loading.map { SaveText.loadPrompt($0.name) } ?? "",
               isPresented: Binding(get: { loading != nil }, set: { if !$0 { loading = nil } }),
               presenting: loading) { save in
            Button(SaveText.load) {
                InteractionSound.activate.play()
                load(save)
            }
            Button(SaveText.cancel, role: .cancel) { InteractionSound.activate.play() }
        } message: { _ in
            Text(SaveText.loadWarning)
        }
        .modifier(DeleteConfirmation(deleting: $deleting, delete: delete))
    }
}
