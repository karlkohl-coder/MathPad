import Foundation
import Observation

/// Owns every sheet and writes them to disk.
///
/// Storage is one JSON file per sheet in
/// `~/Library/Application Support/MathPad/Sheets/`, so a sheet is a plain,
/// inspectable file and a future feature can read them without going through
/// this class.
@MainActor
@Observable
final class SheetStore {
    private(set) var sheets: [Sheet] = []
    var selectedSheetID: Sheet.ID?

    /// Group names in the order the sidebar shows them. Kept separately from the
    /// sheets so a group you just made, and any group you emptied, still exists.
    private(set) var groupOrder: [String] = []

    /// Groups the user has folded away. Stored by name so the sidebar looks the
    /// same after a restart.
    private(set) var collapsedGroups: Set<String> = []

    private let directory: URL
    private var saveTasks: [Sheet.ID: Task<Void, Never>] = [:]

    var selectedSheet: Sheet? {
        guard let id = selectedSheetID else { return nil }
        return sheets.first { $0.id == id }
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        loadGroups()
        loadCollapsed()
        load()
        if sheets.isEmpty { newSheet() }
        selectedSheetID = sheets.first?.id
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MathPad/Sheets", isDirectory: true)
    }

    // MARK: - Loading

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
        sheets = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Sheet.self, from: data)
            }
            .map(migrated)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Brings an older sheet up to the current shape.
    ///
    /// Version 0 had a single prose kind. Everything written back then was body
    /// text — worksheet sentences, not margin notes — so it becomes `.paragraph`,
    /// which is set at formula size. Lines you deliberately mark as a note after
    /// this stay notes: the version stamp makes the conversion run once.
    private func migrated(_ sheet: Sheet) -> Sheet {
        guard sheet.formatVersion < Sheet.currentFormatVersion else { return sheet }
        var updated = sheet
        updated.formatVersion = Sheet.currentFormatVersion
        updated.blocks = sheet.blocks.map { block in
            guard block.kind == .text else { return block }
            var moved = block
            moved.kind = .paragraph
            return moved
        }
        scheduleSave(updated)
        return updated
    }

    // MARK: - Groups

    /// Sections for the sidebar: every known group in order, then the ungrouped
    /// sheets. Groups with no sheets are kept so you can make one and fill it later.
    var sections: [(group: String?, sheets: [Sheet])] {
        var result: [(String?, [Sheet])] = groupOrder.map { name in
            (name, sheets.filter { $0.group == name })
        }
        let ungrouped = sheets.filter { $0.group == nil || !groupOrder.contains($0.group!) }
        if !ungrouped.isEmpty || result.isEmpty {
            result.append((nil, ungrouped))
        }
        return result.map { (group: $0.0, sheets: $0.1) }
    }

    /// A name that is not taken yet, so repeated "Neue Gruppe" clicks do not collide.
    func uniqueGroupName(basedOn base: String = "Neue Gruppe") -> String {
        guard groupOrder.contains(base) else { return base }
        var index = 2
        while groupOrder.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    @discardableResult
    func createGroup(named name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? uniqueGroupName() : trimmed
        guard !groupOrder.contains(final) else { return final }
        groupOrder.append(final)
        saveGroups()
        return final
    }

    func renameGroup(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, let index = groupOrder.firstIndex(of: old) else { return }
        guard !groupOrder.contains(trimmed) else { return }
        groupOrder[index] = trimmed
        if collapsedGroups.remove(old) != nil {
            collapsedGroups.insert(trimmed)
            UserDefaults.standard.set(Array(collapsedGroups), forKey: Self.collapsedKey)
        }
        for sheet in sheets where sheet.group == old {
            var moved = sheet
            moved.group = trimmed
            update(moved)
        }
        saveGroups()
    }

    /// Removes the group; its sheets become ungrouped rather than being deleted.
    func deleteGroup(_ name: String) {
        groupOrder.removeAll { $0 == name }
        setExpanded(true, for: name)
        for sheet in sheets where sheet.group == name {
            var moved = sheet
            moved.group = nil
            update(moved)
        }
        saveGroups()
    }

    func move(_ id: Sheet.ID, toGroup group: String?) {
        guard var sheet = sheets.first(where: { $0.id == id }) else { return }
        if let group { createGroup(named: group) }
        sheet.group = group
        update(sheet)
    }

    func moveGroup(_ name: String, by offset: Int) {
        guard let index = groupOrder.firstIndex(of: name) else { return }
        let target = index + offset
        guard groupOrder.indices.contains(target) else { return }
        groupOrder.swapAt(index, target)
        saveGroups()
    }

    // MARK: Folding

    /// Key for the section without a group, which folds like any other.
    private static let ungroupedKey = "\u{0}ungrouped"
    private static let collapsedKey = "MathPad.collapsedGroups"

    private func foldKey(_ group: String?) -> String { group ?? Self.ungroupedKey }

    func isExpanded(_ group: String?) -> Bool {
        !collapsedGroups.contains(foldKey(group))
    }

    func setExpanded(_ expanded: Bool, for group: String?) {
        let key = foldKey(group)
        if expanded { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        UserDefaults.standard.set(Array(collapsedGroups), forKey: Self.collapsedKey)
    }

    private func loadCollapsed() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.collapsedKey) ?? []
        collapsedGroups = Set(stored)
    }

    private var groupsURL: URL { directory.appendingPathComponent("Groups.json") }

    private func loadGroups() {
        guard let data = try? Data(contentsOf: groupsURL),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return }
        groupOrder = names
    }

    private func saveGroups() {
        guard let data = try? JSONEncoder().encode(groupOrder) else { return }
        try? data.write(to: groupsURL, options: .atomic)
    }

    // MARK: - Mutation

    /// A new sheet lands in the group you are currently looking at, which is
    /// almost always the one you meant.
    @discardableResult
    func newSheet(in group: String? = nil, blocks: [Block]? = nil, title: String? = nil) -> Sheet {
        var sheet = Sheet(group: group ?? selectedSheet?.group)
        if let blocks, !blocks.isEmpty { sheet.blocks = blocks }
        if let title { sheet.title = title }
        sheets.insert(sheet, at: 0)
        selectedSheetID = sheet.id
        scheduleSave(sheet)
        return sheet
    }

    func update(_ sheet: Sheet) {
        guard let index = sheets.firstIndex(where: { $0.id == sheet.id }) else { return }
        var updated = sheet
        updated.updatedAt = .now
        sheets[index] = updated
        scheduleSave(updated)
    }

    func rename(_ id: Sheet.ID, to title: String) {
        guard var sheet = sheets.first(where: { $0.id == id }) else { return }
        sheet.title = title
        update(sheet)
    }

    func delete(_ id: Sheet.ID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        sheets.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(for: id))
        if selectedSheetID == id { selectedSheetID = sheets.first?.id }
        if sheets.isEmpty { newSheet() }
    }

    func duplicate(_ id: Sheet.ID) {
        guard let source = sheets.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.title = source.displayTitle + " Kopie"
        copy.group = source.group
        copy.blocks = source.blocks.map { Block(kind: $0.kind, value: $0.value) }
        copy.createdAt = .now
        copy.updatedAt = .now
        sheets.insert(copy, at: 0)
        selectedSheetID = copy.id
        scheduleSave(copy)
    }

    // MARK: - Saving

    private func url(for id: Sheet.ID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Debounced: typing a formula fires a change per keystroke, and we do not
    /// want a disk write for each one.
    private func scheduleSave(_ sheet: Sheet) {
        saveTasks[sheet.id]?.cancel()
        saveTasks[sheet.id] = Task { [url = url(for: sheet.id)] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(sheet) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Flush everything immediately — used on quit.
    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for sheet in sheets {
            saveTasks[sheet.id]?.cancel()
            if let data = try? encoder.encode(sheet) {
                try? data.write(to: url(for: sheet.id), options: .atomic)
            }
        }
    }
}
