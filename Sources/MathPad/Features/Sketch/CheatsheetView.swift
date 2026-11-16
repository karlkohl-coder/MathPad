import SwiftUI

/// The one screen that teaches the input language. Reachable with ⌘/.
struct CheatsheetView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tastatur-Spickzettel")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Fertig", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 26), GridItem(.flexible(), spacing: 26)],
                          alignment: .leading, spacing: 24) {
                    ForEach(Cheatsheet.sections) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(.tertiary)
                            ForEach(section.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(entry.keys)
                                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2.5)
                                        .background(Color.primary.opacity(0.07),
                                                    in: RoundedRectangle(cornerRadius: 5))
                                        .frame(width: 108, alignment: .leading)
                                    Text(entry.meaning)
                                        .font(.system(size: 12.5))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
        .frame(width: 780, height: 600)
    }
}

// MARK: - Content

enum Cheatsheet {
    struct Entry: Identifiable {
        let keys: String
        let meaning: String
        var id: String { keys + meaning }
    }

    struct Section: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Zeilen", entries: [
            Entry(keys: "↩", meaning: "Neue Zeile gleicher Art"),
            Entry(keys: "⌘↩", meaning: "Neue Textzeile"),
            Entry(keys: "⌫", meaning: "In leerer Zeile: Zeile löschen"),
            Entry(keys: "↑ ↓", meaning: "Zwischen Zeilen wandern"),
            Entry(keys: "⌃⌘↑ / ⌃⌘↓", meaning: "Zeile verschieben"),
            Entry(keys: "⌥⌘1 … ⌥⌘5", meaning: "Formel / Text+Formel / Text / Notiz / Überschrift"),
            Entry(keys: "⌘D", meaning: "Zeile duplizieren"),
            Entry(keys: "⌘Z / ⇧⌘Z", meaning: "Widerrufen / Wiederholen – auch Zeilenart und Löschen"),
        ]),

        Section(title: "Tabellen", entries: [
            Entry(keys: "⇧⌘T", meaning: "Tabelle einfügen (3 × 3) – Größe wählen über die Symbolleiste"),
            Entry(keys: "⇥ / ⇧⇥", meaning: "Nächste / vorige Zelle; in der letzten Zelle neue Zeile"),
            Entry(keys: "↩", meaning: "Zelle darunter; in der letzten Zeile neue Zeile"),
            Entry(keys: "← → ↑ ↓", meaning: "Am Rand einer Zelle in die Nachbarzelle"),
            Entry(keys: "+", meaning: "Knöpfe rechts und unten: Spalte / Zeile anfügen"),
            Entry(keys: "Rechtsklick", meaning: "Zeilen & Spalten einfügen/löschen, Kopfzeile, Ausrichtung, Linien"),
            Entry(keys: "Rand ziehen", meaning: "Spaltenbreite ändern – Doppelklick: automatisch"),
            Entry(keys: "⌘↩", meaning: "Unter der Tabelle mit Text weiterschreiben"),
        ]),

        Section(title: "Formatieren", entries: [
            Entry(keys: "⌘B", meaning: "Fett – in Formeln wie in Notizen"),
            Entry(keys: "⌘I", meaning: "Kursiv"),
            Entry(keys: "⌘U", meaning: "Unterstrichen"),
            Entry(keys: "ohne Auswahl", meaning: "Gilt für die ganze Zeile"),
            Entry(keys: "Menü Format", meaning: "Schriftfarbe und Textmarker"),
        ]),

        Section(title: "Arbeitsblatt einlesen", entries: [
            Entry(keys: "⇧⌘I", meaning: "PDF-Seite oder Bild einlesen"),
            Entry(keys: "Ziehen", meaning: "Datei einfach aufs Blatt ziehen"),
            Entry(keys: "⌘,", meaning: "Erkennung einstellen (Claude Code, KI-Dienst, Apple Vision)"),
            Entry(keys: "⇧⌘N", meaning: "Neue Gruppe für Blätter"),
        ]),

        Section(title: "Text und Formel in einer Zeile", entries: [
            Entry(keys: "⌥⌘2", meaning: "Zeile auf „Text + Formel“ stellen"),
            Entry(keys: "Wörter", meaning: "Du schreibst Text – Kürzel greifen nie mitten im Wort"),
            Entry(keys: "x  f  A", meaning: "Einzelne Buchstaben werden Formel, sobald das Wort fertig ist"),
            Entry(keys: "= < > ^ _ \\", meaning: "Beginnen eine Formel und nehmen den Buchstaben davor mit"),
            Entry(keys: "f(  sin(", meaning: "Funktionsaufruf wird Formel"),
            Entry(keys: "alpha  RR", meaning: "Werden zu α und ℝ, sobald das Wort fertig ist"),
            Entry(keys: "␣", meaning: "Verlässt die Formel (im Index erst den Index)"),
            Entry(keys: "$", meaning: "Von Hand zwischen Text und Formel umschalten"),
            Entry(keys: "Rechtsklick", meaning: "Markieren, dann „ist Text“ / „ist Formel“ wählen"),
            Entry(keys: "⌘V", meaning: "Aus ChatGPT, Claude, Wikipedia, Markdown – Formeln bleiben Formeln"),
            Entry(keys: "⌥⌘L", meaning: "Zeigt, wo \\text{…} steht"),
        ]),

        Section(title: "In der Formel tippen", entries: [
            Entry(keys: "/", meaning: "Bruch – Zähler ist, was links steht"),
            Entry(keys: "^", meaning: "Hochgestellt – auch auf deutscher Tastatur"),
            Entry(keys: "⌃6 / ⌃-", meaning: "Hoch / tief, falls die Tastatur klemmt"),
            Entry(keys: "_", meaning: "Tiefgestellt (Index)"),
            Entry(keys: "→", meaning: "Aus Bruch/Exponent wieder heraus"),
            Entry(keys: "⇥", meaning: "Zum nächsten Platzhalter"),
            Entry(keys: "⇧↩", meaning: "Neue Zeile in Matrix / Fällen"),
            Entry(keys: "( [ {", meaning: "Klammern schließen sich selbst"),
        ]),

        Section(title: "Verwandelt sich beim Tippen", entries: [
            Entry(keys: "alpha, beta …", meaning: "α, β, … (alle griechischen Buchstaben)"),
            Entry(keys: "sqrt / wurzel", meaning: "√ mit Platzhalter"),
            Entry(keys: "bruch", meaning: "Bruch mit zwei Platzhaltern"),
            Entry(keys: "sum / summe", meaning: "∑ mit Grenzen"),
            Entry(keys: "int / integral", meaning: "∫ mit Grenzen"),
            Entry(keys: "lim / grenzwert", meaning: "Limes mit x → a"),
            Entry(keys: "matrix", meaning: "2×2-Matrix"),
            Entry(keys: "faelle", meaning: "Fallunterscheidung"),
            Entry(keys: "infty / unendlich", meaning: "∞"),
        ]),

        Section(title: "Zeichen aus Zeichen", entries: [
            Entry(keys: "->", meaning: "→"),
            Entry(keys: "=>", meaning: "⇒"),
            Entry(keys: "<=>", meaning: "⇔"),
            Entry(keys: "|->", meaning: "↦"),
            Entry(keys: "!=", meaning: "≠"),
            Entry(keys: "<= / >=", meaning: "≤ / ≥"),
            Entry(keys: "RR NN ZZ QQ CC", meaning: "ℝ ℕ ℤ ℚ ℂ"),
            Entry(keys: "...", meaning: "…"),
        ]),

        Section(title: "Wenn du es genau wissen willst", entries: [
            Entry(keys: "⌘K", meaning: "Symbolpalette – nach deutschem Namen suchen"),
            Entry(keys: "⌥⌘L", meaning: "LaTeX-Quelltext dieser Zeile bearbeiten"),
            Entry(keys: "\\befehl", meaning: "Jeder LaTeX-Befehl geht auch direkt"),
            Entry(keys: "esc", meaning: "Palette schließen / zurück zur Formel"),
        ]),

        Section(title: "Weitergeben", entries: [
            Entry(keys: "⇧⌘C", meaning: "Formel als LaTeX kopieren"),
            Entry(keys: "⌥⇧⌘C", meaning: "Formel als MathML (Word, Pages)"),
            Entry(keys: "⇧⌘P", meaning: "Blatt als PDF sichern – A4, mit Seitenumbruch"),
            Entry(keys: "⌘+ / ⌘-", meaning: "Formeln größer / kleiner"),
            Entry(keys: "⌘/", meaning: "Diesen Spickzettel"),
        ]),
    ]
}
