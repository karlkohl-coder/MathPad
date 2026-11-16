import SwiftUI

/// The ⌘K panel: search the whole catalogue by German name, by LaTeX command,
/// or by a few scattered letters, then insert at the caret.
struct CommandPalette: View {
    let onInsert: (MathSymbol) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var category: SymbolCategory?
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var results: [MathSymbol] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty, category == nil {
            let recent = RecentSymbols.symbols()
            return recent.isEmpty ? SymbolCatalog.all : recent + SymbolCatalog.all.filter { symbol in
                !recent.contains(symbol)
            }
        }
        return SymbolSearch.search(query, category: category)
    }

    private var showingRecents: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && category == nil && !RecentSymbols.symbols().isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            categoryBar
            Divider()
            resultList
            Divider()
            footer
        }
        .frame(width: 620, height: 470)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.28), radius: 34, y: 14)
        .onAppear { searchFocused = true }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Symbol suchen – z. B. „bruch“, „integral“, „reelle Zahlen“", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onChange(of: query) { _, _ in selection = 0 }
                .onSubmit(insertSelected)
                .onKeyPress(.downArrow) { move(+1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .onKeyPress(.tab) { move(+1); return .handled }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "Alle", active: category == nil) { category = nil; selection = 0 }
                ForEach(SymbolCategory.allCases) { item in
                    chip(title: item.rawValue, active: category == item) {
                        category = category == item ? nil : item
                        selection = 0
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color.primary.opacity(0.06)),
                            in: Capsule())
                .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if showingRecents {
                        sectionHeader("Zuletzt benutzt")
                    }
                    // Identity comes from the symbol, never from its position: an
                    // index-based `.id()` would make row 0 of "Griechisch" look
                    // like row 0 of "Alle" to SwiftUI, and the lazy stack would
                    // keep showing the old contents when the filter changes.
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, symbol in
                        row(symbol, index: index)
                    }
                    if results.isEmpty {
                        Text("Nichts gefunden. Tipp: Du kannst jeden LaTeX-Befehl auch direkt in die Formel tippen.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selection) { _, new in
                guard results.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(results[new].id, anchor: .center)
                }
            }
            // Picking a category leaves the selection at 0, so `onChange(of:)`
            // above would not fire — scroll back to the top explicitly.
            .onChange(of: category) { _, _ in
                guard let first = results.first else { return }
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private func row(_ symbol: MathSymbol, index: Int) -> some View {
        let active = index == selection
        return HStack(spacing: 12) {
            Text(symbol.preview)
                .font(.system(size: 19))
                .frame(width: 42, height: 30)
                .background(Color.primary.opacity(active ? 0.10 : 0.05),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(symbol.name)
                    .font(.system(size: 13.5, weight: .medium))
                Text(symbol.latex.replacingOccurrences(of: "#0", with: "▢")
                                 .replacingOccurrences(of: "#?", with: "▫"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(symbol.category.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { selection = index; insertSelected() }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "wählen")
            hint("↩", "einfügen")
            hint("esc", "schließen")
            Spacer()
            Text("\(results.count) Symbole")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func insertSelected() {
        guard results.indices.contains(selection) else { return }
        let symbol = results[selection]
        RecentSymbols.record(symbol)
        onInsert(symbol)
    }
}
