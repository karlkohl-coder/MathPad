import Foundation

/// A category in the symbol palette.
enum SymbolCategory: String, CaseIterable, Identifiable, Hashable {
    case structures = "Strukturen"
    case greek = "Griechisch"
    case operators = "Operatoren"
    case relations = "Relationen"
    case arrows = "Pfeile"
    case setsLogic = "Mengen & Logik"
    case calculus = "Analysis"
    case linearAlgebra = "Lineare Algebra"
    case decorations = "Akzente"
    case fonts = "Schriften"
    case misc = "Sonstiges"

    var id: String { rawValue }
}

/// One insertable item.
///
/// `latex` may contain MathLive placeholders: `#0` is where the caret lands,
/// `#?` are the tab stops after it.
struct MathSymbol: Identifiable, Hashable {
    let latex: String
    let name: String
    let preview: String
    let keywords: [String]
    let category: SymbolCategory

    var id: String { "\(category.rawValue)|\(name)|\(latex)" }

    /// Everything the fuzzy matcher may look at.
    var searchCorpus: [String] {
        [name, preview] + keywords + [latex.replacingOccurrences(of: "\\", with: "")]
    }
}

private func s(_ latex: String,
               _ name: String,
               _ preview: String,
               _ keywords: [String],
               _ category: SymbolCategory) -> MathSymbol {
    MathSymbol(latex: latex, name: name, preview: preview, keywords: keywords, category: category)
}

/// The full palette. Everything reachable by name instead of by LaTeX command —
/// this is what makes "you can write anything" usable without knowing LaTeX.
enum SymbolCatalog {

    static let all: [MathSymbol] = structures + greek + operators + relations
        + arrows + setsLogic + calculus + linearAlgebra + decorations + fonts + misc

    // MARK: Structures

    static let structures: [MathSymbol] = [
        s("\\frac{#0}{#?}", "Bruch", "a⁄b", ["bruch", "division", "frac", "geteilt", "quotient"], .structures),
        s("\\sqrt{#0}", "Wurzel", "√", ["wurzel", "sqrt", "quadratwurzel", "radikal"], .structures),
        s("\\sqrt[#?]{#0}", "n-te Wurzel", "ⁿ√", ["wurzel", "kubikwurzel", "nte", "root"], .structures),
        s("#0^{#?}", "Hochgestellt", "xⁿ", ["potenz", "exponent", "hoch", "super"], .structures),
        s("#0_{#?}", "Tiefgestellt", "xₙ", ["index", "tief", "sub", "subscript"], .structures),
        s("#0_{#?}^{#?}", "Index & Exponent", "xᵃ_b", ["index", "exponent", "beides"], .structures),
        s("\\left(#0\\right)", "Klammern", "( )", ["klammer", "runde", "paren"], .structures),
        s("\\left[#0\\right]", "Eckige Klammern", "[ ]", ["klammer", "eckig", "bracket"], .structures),
        s("\\left\\{#0\\right\\}", "Geschweifte Klammern", "{ }", ["klammer", "menge", "brace"], .structures),
        s("\\left|#0\\right|", "Betrag", "|x|", ["betrag", "absolut", "abs"], .structures),
        s("\\left\\|#0\\right\\|", "Norm", "‖x‖", ["norm", "laenge", "betrag"], .structures),
        s("\\left\\langle #0\\right\\rangle", "Spitze Klammern", "⟨ ⟩", ["skalarprodukt", "bra", "ket", "winkel"], .structures),
        s("\\lfloor #0\\rfloor", "Abrunden", "⌊x⌋", ["floor", "abrunden", "gauss"], .structures),
        s("\\lceil #0\\rceil", "Aufrunden", "⌈x⌉", ["ceil", "aufrunden"], .structures),
        s("\\begin{cases}#0 & \\text{falls } #?\\\\ #? & \\text{sonst}\\end{cases}", "Fallunterscheidung", "{…", ["faelle", "cases", "fallunterscheidung", "wenn"], .structures),
        s("\\begin{pmatrix}#0 & #?\\\\ #? & #?\\end{pmatrix}", "Matrix (rund)", "(⋮)", ["matrix", "pmatrix", "2x2"], .structures),
        s("\\begin{bmatrix}#0 & #?\\\\ #? & #?\\end{bmatrix}", "Matrix (eckig)", "[⋮]", ["matrix", "bmatrix"], .structures),
        s("\\begin{vmatrix}#0 & #?\\\\ #? & #?\\end{vmatrix}", "Determinante", "|⋮|", ["determinante", "det", "vmatrix"], .structures),
        s("\\begin{pmatrix}#0\\\\ #?\\\\ #?\\end{pmatrix}", "Spaltenvektor", "(⋮)", ["vektor", "spalte", "spaltenvektor"], .structures),
        s("\\begin{array}{cc}#0 & #?\\\\ #? & #?\\end{array}", "Tabelle", "▦", ["array", "tabelle", "raster"], .structures),
        s("\\binom{#0}{#?}", "Binomialkoeffizient", "(ⁿₖ)", ["binomial", "ueber", "choose", "kombinatorik"], .structures),
        s("\\overset{#?}{#0}", "Darüber", "a̅", ["ueber", "overset", "darueber"], .structures),
        s("\\underset{#?}{#0}", "Darunter", "a̲", ["unter", "underset", "darunter"], .structures),
        s("\\text{#0}", "Text in Formel", "abc", ["text", "wort", "beschriftung"], .structures),
        s("\\underbrace{#0}_{#?}", "Unterklammer", "⏟", ["klammer", "unterklammer", "underbrace"], .structures),
        s("\\overbrace{#0}^{#?}", "Überklammer", "⏞", ["klammer", "ueberklammer", "overbrace"], .structures),
        s("\\begin{array}{c}#0\\\\ #?\\end{array}", "Mehrzeiliger Index", "⋮", ["index", "substack", "mehrzeilig"], .structures),

        // Intervalle
        s("\\left(#0,#?\\right)", "Offenes Intervall", "(a,b)", ["intervall", "offen"], .structures),
        s("\\left[#0,#?\\right]", "Abgeschlossenes Intervall", "[a,b]", ["intervall", "abgeschlossen", "kompakt"], .structures),
        s("\\left(#0,#?\\right]", "Intervall, links offen", "(a,b]", ["intervall", "halboffen", "links offen"], .structures),
        s("\\left[#0,#?\\right)", "Intervall, rechts offen", "[a,b)", ["intervall", "halboffen", "rechts offen"], .structures),

        // Größere Matrizen
        s("\\begin{pmatrix}#0 & #? & #?\\\\ #? & #? & #?\\\\ #? & #? & #?\\end{pmatrix}", "Matrix 3×3", "(⋱)", ["matrix", "3x3", "drei"], .structures),
        s("\\begin{pmatrix}#0 & \\cdots & #?\\\\ \\vdots & \\ddots & \\vdots\\\\ #? & \\cdots & #?\\end{pmatrix}", "Matrix allgemein (n×m)", "(⋯)", ["matrix", "allgemein", "nxm", "punkte", "gross"], .structures),
        s("\\begin{pmatrix}#0 & #? & #?\\end{pmatrix}", "Zeilenvektor", "(a b c)", ["vektor", "zeile", "zeilenvektor"], .structures),
        s("\\left(\\begin{array}{ccc|c}#0 & #? & #? & #?\\\\ #? & #? & #? & #?\\\\ #? & #? & #? & #?\\end{array}\\right)", "Erweiterte Koeffizientenmatrix", "(A|b)", ["gauss", "lgs", "erweitert", "koeffizientenmatrix", "trennstrich"], .structures),
        s("\\begin{pmatrix}1 & 2 & \\cdots & #?\\\\ #0 & #? & \\cdots & #?\\end{pmatrix}", "Permutation (zweizeilig)", "(12⋯)", ["permutation", "zweizeilig", "symmetrische gruppe"], .structures),
    ]

    // MARK: Greek

    static let greek: [MathSymbol] = [
        s("\\alpha", "Alpha", "α", ["alpha", "a"], .greek),
        s("\\beta", "Beta", "β", ["beta", "b"], .greek),
        s("\\gamma", "Gamma", "γ", ["gamma", "g"], .greek),
        s("\\delta", "Delta", "δ", ["delta", "d"], .greek),
        s("\\epsilon", "Epsilon", "ϵ", ["epsilon", "e"], .greek),
        s("\\varepsilon", "Epsilon (var)", "ε", ["epsilon", "var"], .greek),
        s("\\zeta", "Zeta", "ζ", ["zeta"], .greek),
        s("\\eta", "Eta", "η", ["eta"], .greek),
        s("\\theta", "Theta", "θ", ["theta", "winkel"], .greek),
        s("\\vartheta", "Theta (var)", "ϑ", ["theta", "var"], .greek),
        s("\\iota", "Iota", "ι", ["iota"], .greek),
        s("\\kappa", "Kappa", "κ", ["kappa"], .greek),
        s("\\lambda", "Lambda", "λ", ["lambda", "eigenwert"], .greek),
        s("\\mu", "My", "μ", ["mu", "my", "mittelwert"], .greek),
        s("\\nu", "Ny", "ν", ["nu", "ny"], .greek),
        s("\\xi", "Xi", "ξ", ["xi"], .greek),
        s("\\pi", "Pi", "π", ["pi", "kreiszahl"], .greek),
        s("\\rho", "Rho", "ρ", ["rho", "dichte"], .greek),
        s("\\sigma", "Sigma", "σ", ["sigma", "standardabweichung"], .greek),
        s("\\tau", "Tau", "τ", ["tau"], .greek),
        s("\\upsilon", "Ypsilon", "υ", ["upsilon"], .greek),
        s("\\phi", "Phi", "ϕ", ["phi"], .greek),
        s("\\varphi", "Phi (var)", "φ", ["phi", "var"], .greek),
        s("\\chi", "Chi", "χ", ["chi"], .greek),
        s("\\psi", "Psi", "ψ", ["psi", "wellenfunktion"], .greek),
        s("\\omega", "Omega", "ω", ["omega", "kreisfrequenz"], .greek),
        s("\\Gamma", "Gamma (groß)", "Γ", ["gamma", "gross"], .greek),
        s("\\Delta", "Delta (groß)", "Δ", ["delta", "gross", "differenz", "laplace"], .greek),
        s("\\Theta", "Theta (groß)", "Θ", ["theta", "gross"], .greek),
        s("\\Lambda", "Lambda (groß)", "Λ", ["lambda", "gross"], .greek),
        s("\\Xi", "Xi (groß)", "Ξ", ["xi", "gross"], .greek),
        s("\\Pi", "Pi (groß)", "Π", ["pi", "gross", "produkt"], .greek),
        s("\\Sigma", "Sigma (groß)", "Σ", ["sigma", "gross", "summe"], .greek),
        s("\\Upsilon", "Ypsilon (groß)", "Υ", ["upsilon", "gross"], .greek),
        s("\\Phi", "Phi (groß)", "Φ", ["phi", "gross", "fluss"], .greek),
        s("\\Psi", "Psi (groß)", "Ψ", ["psi", "gross"], .greek),
        s("\\Omega", "Omega (groß)", "Ω", ["omega", "gross", "ohm"], .greek),
        s("\\nabla", "Nabla", "∇", ["nabla", "gradient", "del"], .greek),
        s("\\partial", "Partiell", "∂", ["partiell", "partial", "ableitung"], .greek),
        s("\\hbar", "h quer", "ℏ", ["hbar", "planck", "quantenmechanik"], .greek),
        s("\\ell", "Ell", "ℓ", ["ell", "laenge", "l"], .greek),
    ]

    // MARK: Operators

    static let operators: [MathSymbol] = [
        s("\\cdot", "Mal (Punkt)", "·", ["mal", "punkt", "multiplikation", "cdot"], .operators),
        s("\\times", "Mal (Kreuz)", "×", ["mal", "kreuz", "kreuzprodukt", "times"], .operators),
        s("\\div", "Geteilt", "÷", ["geteilt", "division", "div"], .operators),
        s("\\pm", "Plusminus", "±", ["plusminus", "pm"], .operators),
        s("\\mp", "Minusplus", "∓", ["minusplus", "mp"], .operators),
        s("\\ast", "Stern", "∗", ["stern", "faltung", "ast"], .operators),
        s("\\circ", "Verkettung", "∘", ["verkettung", "kringel", "komposition", "circ"], .operators),
        s("\\oplus", "Direkte Summe", "⊕", ["oplus", "direkte summe", "xor"], .operators),
        s("\\otimes", "Tensorprodukt", "⊗", ["otimes", "tensor", "kronecker"], .operators),
        s("\\odot", "Hadamard", "⊙", ["odot", "hadamard", "elementweise"], .operators),
        s("\\sum_{#0}^{#?}", "Summe", "∑", ["summe", "sum", "sigma"], .operators),
        s("\\prod_{#0}^{#?}", "Produkt", "∏", ["produkt", "prod", "pi"], .operators),
        s("\\coprod_{#0}^{#?}", "Koprodukt", "∐", ["koprodukt", "coprod"], .operators),
        s("\\bigcup_{#0}^{#?}", "Große Vereinigung", "⋃", ["vereinigung", "bigcup"], .operators),
        s("\\bigcap_{#0}^{#?}", "Großer Schnitt", "⋂", ["schnitt", "bigcap", "durchschnitt"], .operators),
        s("\\bigoplus_{#0}^{#?}", "Große direkte Summe", "⨁", ["bigoplus", "direkte summe"], .operators),
        s("\\sqrt[3]{#0}", "Kubikwurzel", "∛", ["kubikwurzel", "dritte wurzel"], .operators),
        s("!", "Fakultät", "n!", ["fakultaet", "factorial"], .operators),
        s("\\%", "Prozent", "%", ["prozent", "percent"], .operators),
        s("^\\circ", "Grad", "°", ["grad", "degree", "winkel"], .operators),
        s("\\bmod", "Modulo", "mod", ["modulo", "mod", "rest"], .operators),
        s("\\gcd(#0,#?)", "ggT", "ggT", ["ggt", "gcd", "teiler"], .operators),
    ]

    // MARK: Relations

    static let relations: [MathSymbol] = [
        s("=", "Gleich", "=", ["gleich", "equals"], .relations),
        s("\\neq", "Ungleich", "≠", ["ungleich", "neq", "nicht gleich"], .relations),
        s("\\approx", "Ungefähr", "≈", ["ungefaehr", "approx", "circa"], .relations),
        s("\\equiv", "Kongruent", "≡", ["kongruent", "equiv", "identisch"], .relations),
        s("\\sim", "Ähnlich", "∼", ["aehnlich", "sim", "proportional"], .relations),
        s("\\simeq", "Asymptotisch gleich", "≃", ["simeq", "asymptotisch"], .relations),
        s("\\cong", "Isomorph", "≅", ["isomorph", "cong", "kongruent"], .relations),
        s("\\propto", "Proportional", "∝", ["proportional", "propto"], .relations),
        s("<", "Kleiner", "<", ["kleiner", "less"], .relations),
        s(">", "Größer", ">", ["groesser", "greater"], .relations),
        s("\\leq", "Kleiner gleich", "≤", ["kleinergleich", "leq", "le"], .relations),
        s("\\geq", "Größer gleich", "≥", ["groessergleich", "geq", "ge"], .relations),
        s("\\ll", "Viel kleiner", "≪", ["viel kleiner", "ll"], .relations),
        s("\\gg", "Viel größer", "≫", ["viel groesser", "gg"], .relations),
        s("\\prec", "Vorgänger", "≺", ["prec", "ordnung"], .relations),
        s("\\succ", "Nachfolger", "≻", ["succ", "ordnung"], .relations),
        s("\\doteq", "Soll gleich", "≐", ["doteq", "soll"], .relations),
        s("\\coloneqq", "Definiert als", "≔", ["definiert", "coloneqq", "definition", ":="], .relations),
        s("\\perp", "Senkrecht", "⊥", ["senkrecht", "orthogonal", "perp"], .relations),
        s("\\parallel", "Parallel", "∥", ["parallel"], .relations),
        s("\\mid", "Teilt", "∣", ["teilt", "mid", "bedingung"], .relations),
        s("\\nmid", "Teilt nicht", "∤", ["teilt nicht", "nmid"], .relations),
    ]

    // MARK: Arrows

    static let arrows: [MathSymbol] = [
        s("\\to", "Pfeil rechts", "→", ["pfeil", "rechts", "to", "abbildung"], .arrows),
        s("\\leftarrow", "Pfeil links", "←", ["pfeil", "links"], .arrows),
        s("\\leftrightarrow", "Pfeil beidseitig", "↔", ["pfeil", "beidseitig"], .arrows),
        s("\\Rightarrow", "Folgt", "⇒", ["folgt", "impliziert", "implies", "doppelpfeil"], .arrows),
        s("\\Leftarrow", "Folgt aus", "⇐", ["folgt aus", "impliziert"], .arrows),
        s("\\iff", "Genau dann wenn", "⇔", ["genau dann", "aequivalent", "iff", "gdw"], .arrows),
        s("\\mapsto", "Wird abgebildet auf", "↦", ["abbildung", "mapsto", "zuordnung"], .arrows),
        s("\\uparrow", "Pfeil hoch", "↑", ["pfeil", "hoch"], .arrows),
        s("\\downarrow", "Pfeil runter", "↓", ["pfeil", "runter"], .arrows),
        s("\\hookrightarrow", "Einbettung", "↪", ["einbettung", "injektiv", "hook"], .arrows),
        s("\\twoheadrightarrow", "Surjektion", "↠", ["surjektiv", "twohead"], .arrows),
        s("\\rightrightarrows", "Gleichmäßig", "⇉", ["gleichmaessig", "doppelpfeil"], .arrows),
        s("\\xrightarrow{#0}", "Pfeil mit Beschriftung", "→ᶠ", ["pfeil", "beschriftet", "xrightarrow"], .arrows),
        s("\\longrightarrow{}", "Langer Pfeil", "⟶", ["pfeil", "lang"], .arrows),
        s("\\rightsquigarrow", "Schlangenpfeil", "⇝", ["schlange", "squig"], .arrows),

        s("#0\\colon #? \\to #?", "Abbildung deklarieren", "f: A→B", ["abbildung", "funktion", "deklarieren", "doppelpunkt"], .arrows),
        s("#0\\colon #? \\to #?,\\ #? \\mapsto #?", "Abbildung mit Vorschrift", "f: x↦…", ["abbildung", "vorschrift", "mapsto", "zuordnung"], .arrows),
    ]

    // MARK: Sets & logic

    static let setsLogic: [MathSymbol] = [
        s("\\in", "Element von", "∈", ["element", "in", "enthalten"], .setsLogic),
        s("\\notin", "Kein Element", "∉", ["kein element", "notin"], .setsLogic),
        s("\\ni", "Enthält", "∋", ["enthaelt", "ni"], .setsLogic),
        s("\\subset", "Teilmenge", "⊂", ["teilmenge", "subset"], .setsLogic),
        s("\\subseteq", "Teilmenge oder gleich", "⊆", ["teilmenge", "subseteq"], .setsLogic),
        s("\\supset", "Obermenge", "⊃", ["obermenge", "supset"], .setsLogic),
        s("\\supseteq", "Obermenge oder gleich", "⊇", ["obermenge", "supseteq"], .setsLogic),
        s("\\cup", "Vereinigung", "∪", ["vereinigung", "cup", "oder"], .setsLogic),
        s("\\cap", "Schnitt", "∩", ["schnitt", "cap", "durchschnitt", "und"], .setsLogic),
        s("\\setminus", "Ohne", "∖", ["ohne", "differenz", "setminus", "minus"], .setsLogic),
        s("\\emptyset", "Leere Menge", "∅", ["leere menge", "emptyset", "leer"], .setsLogic),
        s("\\varnothing", "Leere Menge (var)", "⌀", ["leere menge", "varnothing"], .setsLogic),
        s("\\mathbb{N}", "Natürliche Zahlen", "ℕ", ["natuerliche", "N", "zahlen"], .setsLogic),
        s("\\mathbb{Z}", "Ganze Zahlen", "ℤ", ["ganze", "Z", "zahlen"], .setsLogic),
        s("\\mathbb{Q}", "Rationale Zahlen", "ℚ", ["rationale", "Q", "zahlen"], .setsLogic),
        s("\\mathbb{R}", "Reelle Zahlen", "ℝ", ["reelle", "R", "zahlen"], .setsLogic),
        s("\\mathbb{C}", "Komplexe Zahlen", "ℂ", ["komplexe", "C", "zahlen"], .setsLogic),
        s("\\mathbb{F}_{#0}", "Endlicher Körper", "𝔽", ["koerper", "field", "endlich"], .setsLogic),
        s("\\mathcal{P}(#0)", "Potenzmenge", "𝒫", ["potenzmenge", "power set"], .setsLogic),
        s("\\forall", "Für alle", "∀", ["fuer alle", "all", "forall", "quantor"], .setsLogic),
        s("\\exists", "Es existiert", "∃", ["existiert", "exists", "quantor"], .setsLogic),
        s("\\nexists", "Existiert nicht", "∄", ["existiert nicht", "nexists"], .setsLogic),
        s("\\land", "Und", "∧", ["und", "and", "konjunktion", "land"], .setsLogic),
        s("\\lor", "Oder", "∨", ["oder", "or", "disjunktion", "lor"], .setsLogic),
        s("\\lnot", "Nicht", "¬", ["nicht", "not", "negation"], .setsLogic),
        s("\\models", "Modelliert", "⊨", ["models", "erfuellt"], .setsLogic),
        s("\\vdash", "Beweisbar", "⊢", ["vdash", "beweisbar", "ableitbar"], .setsLogic),
        s("\\therefore", "Daraus folgt", "∴", ["daraus folgt", "therefore"], .setsLogic),
        s("\\because", "Weil", "∵", ["weil", "because"], .setsLogic),
        s("\\square", "Beweisende", "□", ["qed", "beweisende", "square", "box"], .setsLogic),
        s("\\aleph", "Aleph", "ℵ", ["aleph", "kardinalzahl", "unendlich"], .setsLogic),

        // Indizierte und potenzierte Zahlenbereiche
        s("\\mathbb{R}^{#0}", "Reeller Vektorraum ℝⁿ", "ℝⁿ", ["vektorraum", "rn", "reell", "hoch n"], .setsLogic),
        s("\\mathbb{R}_{>0}", "Positive reelle Zahlen", "ℝ₊", ["positiv", "reell", "groesser null"], .setsLogic),
        s("\\mathbb{R}_{\\ge 0}", "Nichtnegative reelle Zahlen", "ℝ≥0", ["nichtnegativ", "reell", "groesser gleich null"], .setsLogic),
        s("\\mathbb{Z}/#0\\mathbb{Z}", "Restklassen", "ℤ/nℤ", ["restklassen", "modulo", "quotient", "zn"], .setsLogic),

        s("#0 \\times #?", "Kartesisches Produkt", "A×B", ["kartesisch", "produkt", "kreuz", "paare"], .setsLogic),
        s("\\{#0 \\in #? \\mid #?\\}", "Menge mit Bedingung", "{x | …}", ["menge", "bedingung", "sodass", "beschreiben"], .setsLogic),
        s("\\subsetneq", "Echte Teilmenge", "⊊", ["echte teilmenge", "subsetneq", "strikt"], .setsLogic),
        s("#0^{\\complement}", "Komplement", "Aᶜ", ["komplement", "gegenmenge"], .setsLogic),
        s("\\left|#0\\right|", "Mächtigkeit", "|M|", ["maechtigkeit", "kardinalitaet", "anzahl elemente"], .setsLogic),
    ]

    // MARK: Calculus

    static let calculus: [MathSymbol] = [
        s("\\int_{#0}^{#?}", "Integral", "∫", ["integral", "int", "stammfunktion"], .calculus),
        s("\\int", "Unbestimmtes Integral", "∫", ["integral", "unbestimmt"], .calculus),
        s("\\iint", "Doppelintegral", "∬", ["doppelintegral", "iint"], .calculus),
        s("\\iiint", "Dreifachintegral", "∭", ["dreifachintegral", "iiint"], .calculus),
        s("\\oint", "Kurvenintegral", "∮", ["kurvenintegral", "geschlossen", "oint"], .calculus),
        s("\\lim_{#0 \\to #?}", "Grenzwert", "lim", ["grenzwert", "limes", "lim"], .calculus),
        s("\\limsup_{#0}", "Limes superior", "limsup", ["limsup", "grenzwert"], .calculus),
        s("\\liminf_{#0}", "Limes inferior", "liminf", ["liminf", "grenzwert"], .calculus),
        s("\\infty", "Unendlich", "∞", ["unendlich", "infty", "infinity"], .calculus),
        s("\\frac{\\mathrm{d}#0}{\\mathrm{d}#?}", "Ableitung", "d/dx", ["ableitung", "differential", "derivative"], .calculus),
        s("\\frac{\\partial #0}{\\partial #?}", "Partielle Ableitung", "∂/∂x", ["partielle ableitung", "partial"], .calculus),
        s("\\frac{\\mathrm{d}^{#?}#0}{\\mathrm{d}#?^{#?}}", "n-te Ableitung", "dⁿ/dxⁿ", ["ableitung", "hoehere"], .calculus),
        s("#0'", "Strich-Ableitung", "f′", ["ableitung", "strich", "prime"], .calculus),
        s("\\dot{#0}", "Punkt-Ableitung", "ẋ", ["ableitung", "punkt", "zeit"], .calculus),
        s("\\nabla #0", "Gradient", "∇f", ["gradient", "nabla"], .calculus),
        s("\\nabla \\cdot #0", "Divergenz", "∇·F", ["divergenz", "div"], .calculus),
        s("\\nabla \\times #0", "Rotation", "∇×F", ["rotation", "curl", "rot"], .calculus),
        s("\\Delta #0", "Laplace", "Δf", ["laplace", "delta"], .calculus),
        s("\\sin", "Sinus", "sin", ["sinus", "sin", "trigonometrie"], .calculus),
        s("\\cos", "Kosinus", "cos", ["kosinus", "cos"], .calculus),
        s("\\tan", "Tangens", "tan", ["tangens", "tan"], .calculus),
        s("\\arcsin", "Arkussinus", "arcsin", ["arcsin", "umkehr"], .calculus),
        s("\\arccos", "Arkuskosinus", "arccos", ["arccos"], .calculus),
        s("\\arctan", "Arkustangens", "arctan", ["arctan"], .calculus),
        s("\\sinh", "Sinus hyperbolicus", "sinh", ["sinh", "hyperbolisch"], .calculus),
        s("\\cosh", "Kosinus hyperbolicus", "cosh", ["cosh", "hyperbolisch"], .calculus),
        s("\\tanh", "Tangens hyperbolicus", "tanh", ["tanh", "hyperbolisch"], .calculus),
        s("\\exp", "Exponentialfunktion", "exp", ["exponential", "exp", "e"], .calculus),
        s("\\ln", "Natürlicher Logarithmus", "ln", ["logarithmus", "ln", "natuerlich"], .calculus),
        s("\\log_{#0}", "Logarithmus", "log", ["logarithmus", "log"], .calculus),
        s("\\max_{#0}", "Maximum", "max", ["maximum", "max"], .calculus),
        s("\\min_{#0}", "Minimum", "min", ["minimum", "min"], .calculus),
        s("\\sup_{#0}", "Supremum", "sup", ["supremum", "sup"], .calculus),
        s("\\inf_{#0}", "Infimum", "inf", ["infimum", "inf"], .calculus),
        s("\\operatorname*{arg\\,max}_{#0}", "Argmax", "argmax", ["argmax", "arg max"], .calculus),
        s("\\operatorname*{arg\\,min}_{#0}", "Argmin", "argmin", ["argmin", "arg min"], .calculus),
        s("\\mathcal{O}(#0)", "Landau-O", "𝒪", ["landau", "o notation", "komplexitaet"], .calculus),
    ]

    // MARK: Linear algebra

    static let linearAlgebra: [MathSymbol] = [
        s("\\vec{#0}", "Vektorpfeil", "v⃗", ["vektor", "pfeil", "vec"], .linearAlgebra),
        s("\\mathbf{#0}", "Fett (Vektor)", "𝐯", ["vektor", "fett", "bold"], .linearAlgebra),
        s("#0^{\\mathsf{T}}", "Transponiert", "Aᵀ", ["transponiert", "transpose"], .linearAlgebra),
        s("#0^{-1}", "Inverse", "A⁻¹", ["inverse", "invers"], .linearAlgebra),
        s("#0^{\\dagger}", "Adjungiert", "A†", ["adjungiert", "dagger", "hermitesch"], .linearAlgebra),
        s("#0^{*}", "Konjugiert", "z*", ["konjugiert", "stern"], .linearAlgebra),
        s("\\overline{#0}", "Konjugiert (Strich)", "z̄", ["konjugiert", "strich", "overline"], .linearAlgebra),
        s("\\det(#0)", "Determinante", "det", ["determinante", "det"], .linearAlgebra),
        s("\\operatorname{tr}(#0)", "Spur", "tr", ["spur", "trace"], .linearAlgebra),
        s("\\operatorname{rank}(#0)", "Rang", "rank", ["rang", "rank"], .linearAlgebra),
        s("\\dim(#0)", "Dimension", "dim", ["dimension", "dim"], .linearAlgebra),
        s("\\ker(#0)", "Kern", "ker", ["kern", "kernel", "nullraum"], .linearAlgebra),
        s("\\operatorname{im}(#0)", "Bild", "im", ["bild", "image"], .linearAlgebra),
        s("\\operatorname{span}\\{#0\\}", "Spann", "span", ["span", "aufspannen", "huelle"], .linearAlgebra),
        s("\\langle #0, #?\\rangle", "Skalarprodukt", "⟨u,v⟩", ["skalarprodukt", "inneres produkt"], .linearAlgebra),
        s("#0 \\times #?", "Kreuzprodukt", "u×v", ["kreuzprodukt", "vektorprodukt"], .linearAlgebra),
        s("\\|#0\\|_{#?}", "Norm mit Index", "‖v‖₂", ["norm", "laenge"], .linearAlgebra),
        s("\\mathbb{1}", "Einheitsmatrix", "𝟙", ["einheitsmatrix", "identitaet", "eins"], .linearAlgebra),
        s("\\delta_{#0#?}", "Kronecker-Delta", "δᵢⱼ", ["kronecker", "delta"], .linearAlgebra),
        s("\\oplus", "Direkte Summe", "⊕", ["direkte summe", "oplus"], .linearAlgebra),

        s("S_{#0}", "Symmetrische Gruppe", "Sₙ", ["symmetrische gruppe", "permutation", "sn"], .linearAlgebra),
        s("\\operatorname{sgn}(#0)", "Signum", "sgn", ["signum", "vorzeichen", "permutation"], .linearAlgebra),
        s("\\mathrm{GL}_{#0}(#?)", "Allgemeine lineare Gruppe", "GLₙ", ["gl", "invertierbar", "gruppe"], .linearAlgebra),
        s("E_{#0}", "Einheitsmatrix Eₙ", "Eₙ", ["einheitsmatrix", "identitaet", "en"], .linearAlgebra),
        s("\\operatorname{diag}(#0,#?)", "Diagonalmatrix", "diag", ["diagonal", "diagonalmatrix"], .linearAlgebra),
        s("#0^{\\perp}", "Orthogonales Komplement", "U⊥", ["orthogonal", "komplement", "senkrecht"], .linearAlgebra),
        s("\\chi_{#0}", "Charakteristisches Polynom", "χ", ["charakteristisch", "polynom", "eigenwert"], .linearAlgebra),
        s("\\operatorname{Eig}(#0,#?)", "Eigenraum", "Eig", ["eigenraum", "eigenwert", "eigenvektor"], .linearAlgebra),
        s("\\operatorname{Hom}(#0,#?)", "Homomorphismen", "Hom", ["hom", "homomorphismus", "lineare abbildungen"], .linearAlgebra),
        s("\\operatorname{Mat}_{#0 \\times #?}(#?)", "Matrizenraum", "Mat", ["matrizenraum", "mat", "menge der matrizen"], .linearAlgebra),
        s("\\mathcal{B}", "Basis", "ℬ", ["basis"], .linearAlgebra),
    ]

    // MARK: Decorations

    static let decorations: [MathSymbol] = [
        s("\\hat{#0}", "Hut", "x̂", ["hut", "hat", "schaetzer", "operator"], .decorations),
        s("\\bar{#0}", "Querstrich", "x̄", ["quer", "bar", "mittelwert"], .decorations),
        s("\\tilde{#0}", "Tilde", "x̃", ["tilde"], .decorations),
        s("\\widetilde{#0}", "Breite Tilde", "≈̃", ["tilde", "breit"], .decorations),
        s("\\widehat{#0}", "Breiter Hut", "^", ["hut", "breit"], .decorations),
        s("\\dot{#0}", "Punkt", "ẋ", ["punkt", "ableitung"], .decorations),
        s("\\ddot{#0}", "Doppelpunkt", "ẍ", ["doppelpunkt", "zweite ableitung"], .decorations),
        s("\\vec{#0}", "Pfeil", "v⃗", ["pfeil", "vektor"], .decorations),
        s("\\underline{#0}", "Unterstrichen", "x̲", ["unterstrichen", "underline"], .decorations),
        s("\\overline{#0}", "Überstrichen", "x̄", ["ueberstrichen", "overline", "abschluss"], .decorations),
        s("\\overrightarrow{#0}", "Langer Pfeil darüber", "AB⃗", ["pfeil", "strecke"], .decorations),
        s("\\boxed{#0}", "Umrahmt", "▢", ["rahmen", "box", "ergebnis"], .decorations),
        s("\\cancel{#0}", "Durchgestrichen", "x̸", ["durchgestrichen", "kuerzen", "cancel"], .decorations),
    ]

    // MARK: Fonts

    static let fonts: [MathSymbol] = [
        s("\\mathbb{#0}", "Doppelstrich", "𝔸", ["blackboard", "doppelstrich", "mengen", "bb"], .fonts),
        s("\\mathcal{#0}", "Kalligrafisch", "𝒜", ["kalligrafisch", "cal", "schoen"], .fonts),
        s("\\mathfrak{#0}", "Fraktur", "𝔄", ["fraktur", "frak", "algebra", "ideal"], .fonts),
        s("\\mathbf{#0}", "Fett", "𝐀", ["fett", "bold"], .fonts),
        s("\\mathit{#0}", "Kursiv", "𝐴", ["kursiv", "italic"], .fonts),
        s("\\mathrm{#0}", "Aufrecht", "A", ["aufrecht", "roman", "rm", "einheit"], .fonts),
        s("\\mathsf{#0}", "Serifenlos", "𝖠", ["serifenlos", "sans"], .fonts),
        s("\\texttt{#0}", "Schreibmaschine", "A", ["monospace", "code", "tt"], .fonts),
        s("\\operatorname{#0}", "Eigener Operator", "op", ["operator", "funktionsname"], .fonts),
        s("\\color{#0}{#?}", "Farbe", "■", ["farbe", "color", "markieren"], .fonts),
    ]

    // MARK: Misc

    static let misc: [MathSymbol] = [
        s("\\ldots", "Punkte", "…", ["punkte", "dots", "auslassung"], .misc),
        s("\\cdots", "Punkte (mittig)", "⋯", ["punkte", "cdots"], .misc),
        s("\\vdots", "Punkte (vertikal)", "⋮", ["punkte", "vdots"], .misc),
        s("\\ddots", "Punkte (diagonal)", "⋱", ["punkte", "ddots"], .misc),
        s("\\quad", "Abstand", "␣", ["abstand", "quad", "leerzeichen"], .misc),
        s("\\qquad", "Großer Abstand", "␣␣", ["abstand", "qquad"], .misc),
        s("\\angle", "Winkel", "∠", ["winkel", "angle"], .misc),
        s("\\measuredangle", "Gemessener Winkel", "∡", ["winkel", "gemessen"], .misc),
        s("\\triangle", "Dreieck", "△", ["dreieck", "triangle"], .misc),
        s("\\bigstar", "Stern", "★", ["stern", "star"], .misc),
        s("\\checkmark", "Haken", "✓", ["haken", "check", "richtig"], .misc),
        s("\\hbar", "h quer", "ℏ", ["planck", "hbar"], .misc),
        s("\\Re", "Realteil", "ℜ", ["realteil", "re", "komplex"], .misc),
        s("\\Im", "Imaginärteil", "ℑ", ["imaginaerteil", "im", "komplex"], .misc),
        s("\\imath", "i (ohne Punkt)", "ı", ["imaginaer", "i"], .misc),
        s("\\prime", "Strich", "′", ["strich", "prime", "ableitung"], .misc),
        s("\\star", "Stern (Operator)", "⋆", ["stern", "star", "operator"], .misc),
        s("\\dagger", "Kreuz", "†", ["dagger", "kreuz", "adjungiert"], .misc),
        s("\\infty", "Unendlich", "∞", ["unendlich", "infinity"], .misc),
        s("P(#0)", "Wahrscheinlichkeit", "P(A)", ["wahrscheinlichkeit", "probability"], .misc),
        s("\\mathbb{E}[#0]", "Erwartungswert", "𝔼", ["erwartungswert", "expectation"], .misc),
        s("\\operatorname{Var}(#0)", "Varianz", "Var", ["varianz", "variance"], .misc),
        s("\\operatorname{Cov}(#0,#?)", "Kovarianz", "Cov", ["kovarianz", "covariance"], .misc),
        s("\\sim \\mathcal{N}(#0,#?)", "Normalverteilt", "𝒩", ["normalverteilung", "gauss", "verteilt"], .misc),
    ]
}
