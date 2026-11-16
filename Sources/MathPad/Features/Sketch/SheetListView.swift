import SwiftUI

/// The sidebar: sheets, sorted into groups, plus the mode switcher once a
/// second feature exists.
struct SheetListView: View {
    @Environment(AppModel.self) private var model

    @State private var renamingSheet: Sheet.ID?
    @State private var sheetDraft = ""
    @State private var renamingGroup: String?
    @State private var groupDraft = ""

    private var store: SheetStore { model.store }

    var body: some View {
        @Bindable var store = model.store

        VStack(spacing: 0) {
            if FeatureRegistry.shared.showsSwitcher {
                FeatureSwitcher()
                Divider()
            }

            List(selection: $store.selectedSheetID) {
                ForEach(store.sections, id: \.group) { section in
                    Section(isExpanded: Binding(
                        get: { store.isExpanded(section.group) },
                        set: { store.setExpanded($0, for: section.group) }
                    )) {
                        ForEach(section.sheets) { sheet in
                            row(sheet).tag(sheet.id)
                        }
                        if section.sheets.isEmpty {
                            Text("leer")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 2)
                        }
                    } header: {
                        header(for: section.group)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Gruppe umbenennen", isPresented: Binding(
            get: { renamingGroup != nil },
            set: { if !$0 { renamingGroup = nil } }
        )) {
            TextField("Name", text: $groupDraft)
            Button("Abbrechen", role: .cancel) { renamingGroup = nil }
            Button("Sichern") {
                if let old = renamingGroup { store.renameGroup(old, to: groupDraft) }
                renamingGroup = nil
            }
        }
    }

    // MARK: Group headers

    @ViewBuilder
    private func header(for group: String?) -> some View {
        if let group {
            // The count stays useful when the group is folded away.
            Text(verbatim: "\(group)  ·  \(store.sections.first { $0.group == group }?.sheets.count ?? 0)")
                .contextMenu {
                    Button("Umbenennen …") {
                        groupDraft = group
                        renamingGroup = group
                    }
                    Button("Neues Blatt hier") {
                        model.newSheet(in: group)
                    }
                    Divider()
                    Button("Nach oben") { store.moveGroup(group, by: -1) }
                    Button("Nach unten") { store.moveGroup(group, by: +1) }
                    Divider()
                    Button("Gruppe auflösen", role: .destructive) {
                        store.deleteGroup(group)
                    }
                }
        } else {
            Text("Blätter")
        }
    }

    // MARK: Sheet rows

    @ViewBuilder
    private func row(_ sheet: Sheet) -> some View {
        if renamingSheet == sheet.id {
            TextField("Titel", text: $sheetDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    store.rename(sheet.id, to: sheetDraft)
                    renamingSheet = nil
                }
                .onExitCommand { renamingSheet = nil }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(sheet.displayTitle)
                    .lineLimit(1)
                Text(sheet.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 1)
            .contextMenu {
                Button("Umbenennen") {
                    sheetDraft = sheet.displayTitle
                    renamingSheet = sheet.id
                }
                Button("Duplizieren") { store.duplicate(sheet.id) }

                Menu("In Gruppe bewegen") {
                    Button("Ohne Gruppe") { store.move(sheet.id, toGroup: nil) }
                    if !store.groupOrder.isEmpty { Divider() }
                    ForEach(store.groupOrder, id: \.self) { name in
                        Button(name) { store.move(sheet.id, toGroup: name) }
                            .disabled(sheet.group == name)
                    }
                    Divider()
                    Button("Neue Gruppe …") {
                        let name = store.createGroup(named: store.uniqueGroupName())
                        store.move(sheet.id, toGroup: name)
                        groupDraft = name
                        renamingGroup = name
                    }
                }

                Divider()
                Button("Löschen", role: .destructive) { store.delete(sheet.id) }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                model.newSheet()
            } label: {
                Label("Neues Blatt", systemImage: "plus")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                let name = store.createGroup(named: store.uniqueGroupName())
                groupDraft = name
                renamingGroup = name
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Neue Gruppe")

            Button {
                model.importWorksheet()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .buttonStyle(.plain)
            .help("Arbeitsblatt einlesen (⇧⌘I)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

/// Only shown once more than one feature is registered.
struct FeatureSwitcher: View {
    @State private var registry = FeatureRegistry.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(registry.features) { feature in
                Button {
                    registry.activeID = feature.id
                } label: {
                    Label(feature.title, systemImage: feature.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 26)
                        .background(registry.activeID == feature.id ? Color.accentColor.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(feature.title)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
