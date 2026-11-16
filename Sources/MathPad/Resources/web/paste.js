/* MathPad — reading pasted text and formulas.
 *
 * Copying from ChatGPT, Claude, Wikipedia, a lecture page or a Markdown file puts
 * formulas on the clipboard in very different shapes. This file turns all of
 * them into one neutral structure — paragraphs made of text runs and LaTeX runs —
 * which editor.js then drops into the sheet as the right kind of line.
 *
 * Order of trust:
 *   1. HTML with the TeX source attached (KaTeX, MathJax, Wikipedia): exact.
 *   2. HTML with bare MathML: converted element by element.
 *   3. Plain text with $…$, \(…\), \[…\]: exact.
 *   4. Plain text as browsers produce it from rendered KaTeX, where every symbol
 *      appears twice: repaired as well as the text allows.
 *
 * Pure functions only; nothing here touches the sheet.
 */

(() => {
  "use strict";

  // ------------------------------------------------------------ structure

  /* A paragraph is one of
       { type: "line", heading: bool, runs: Run[] }
       { type: "display", latex }
       { type: "table", header: bool, rows: Run[][][] }
     and a run is { t: "text", text, bold, italic } or { t: "math", latex }. */

  const textRun = (text, style = {}) => ({ t: "text", text, bold: !!style.bold, italic: !!style.italic });
  const mathRun = (latex) => ({ t: "math", latex: latex.trim() });

  const hasMath = (paragraphs) => paragraphs.some((p) =>
    p.type === "display"
    || (p.type === "line" && p.runs.some((r) => r.t === "math"))
    || (p.type === "table" && p.rows.some((row) => row.some((cell) => cell.some((r) => r.t === "math")))));

  // ------------------------------------------------------------ unicode

  /* Mathematical Alphanumeric Symbols (𝑥, 𝐀, 𝔸 …) are what MathML turns letters
     into. Italic and bold variants mean nothing more than "a variable"; the
     double-struck ones do carry meaning and become \mathbb. */
  function normalizeMathChars(text) {
    let out = "";
    for (const ch of text) {
      const code = ch.codePointAt(0);
      if (code >= 0x1d538 && code <= 0x1d56b) {
        out += `\\mathbb{${ch.normalize("NFKC")}}`;
      } else if ((code >= 0x1d400 && code <= 0x1d7ff) || code === 0x210e) {
        out += ch.normalize("NFKC");
      } else {
        out += ch;
      }
    }
    return out;
  }

  // Wikipedia wraps every formula in {\displaystyle …}.
  const unwrapDisplaystyle = (tex) => {
    const wrapped = /^\s*\{\\displaystyle\s*([\s\S]*)\}\s*$/.exec(tex);
    return wrapped ? wrapped[1] : tex;
  };

  const MATH_ALNUM = /[\u{1d400}-\u{1d7ff}ℎ]/u;

  // ------------------------------------------------------------ LaTeX out

  /* Inside \text{…} these characters are commands, not letters. */
  function escapeTextLatex(text) {
    return text.replace(/[\\{}$&#^_%~]/g, (ch) => ({
      "\\": "\\textbackslash{}",
      "{": "\\{",
      "}": "\\}",
      "$": "\\$",
      "&": "\\&",
      "#": "\\#",
      "^": "\\textasciicircum{}",
      "_": "\\_",
      "%": "\\%",
      "~": "\\textasciitilde{}",
    })[ch]);
  }

  /** Runs as the LaTeX a "Text + Formel" line stores. */
  function runsToLatex(runs) {
    let out = "";
    for (const run of runs) {
      if (run.t === "math") {
        if (!run.latex) continue;
        // Two formulas in a row must not melt into one command: \alpha x.
        if (/\\[a-zA-Z]+$/.test(out) && /^[a-zA-Z]/.test(run.latex)) out += " ";
        out += run.latex;
        continue;
      }
      if (!run.text) continue;
      let body = `\\text{${escapeTextLatex(run.text)}}`;
      if (run.bold && run.italic) body = `\\textbf{\\textit{${escapeTextLatex(run.text)}}}`;
      else if (run.bold) body = `\\textbf{${escapeTextLatex(run.text)}}`;
      else if (run.italic) body = `\\textit{${escapeTextLatex(run.text)}}`;
      out += body;
    }
    return out;
  }

  const escapeHTML = (text) =>
    text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  /** Text-only runs as the HTML a "Text" line stores. */
  function runsToHTML(runs) {
    return runs.map((run) => {
      let html = escapeHTML(run.text || "");
      if (run.italic) html = `<i>${html}</i>`;
      if (run.bold) html = `<b>${html}</b>`;
      return html;
    }).join("");
  }

  /** Joins neighbouring runs of the same style and trims the ends of a line. */
  function tidyRuns(runs) {
    const merged = [];
    for (const run of runs) {
      const last = merged[merged.length - 1];
      if (run.t === "text" && !run.text) continue;
      if (run.t === "math" && !run.latex) continue;
      if (last && run.t === "text" && last.t === "text"
          && last.bold === run.bold && last.italic === run.italic) {
        last.text += run.text;
      } else {
        merged.push({ ...run });
      }
    }
    for (const run of merged) {
      if (run.t === "text") run.text = run.text.replace(/[ \t\u00a0]+/g, " ");
    }
    // Leading and trailing blanks of the whole line go; inner ones stay, they
    // are the space between a word and a formula.
    while (merged.length && merged[0].t === "text" && !merged[0].text.trim()) merged.shift();
    while (merged.length && merged.at(-1).t === "text" && !merged.at(-1).text.trim()) merged.pop();
    if (merged.length && merged[0].t === "text") merged[0].text = merged[0].text.replace(/^\s+/, "");
    if (merged.length && merged.at(-1).t === "text") merged.at(-1).text = merged.at(-1).text.replace(/\s+$/, "");
    return merged;
  }

  // ------------------------------------------------------------ MathML

  const MO_LATEX = {
    "∘": "\\circ", "∈": "\\in", "∉": "\\notin", "⊂": "\\subset", "⊆": "\\subseteq",
    "⊃": "\\supset", "⊇": "\\supseteq", "∪": "\\cup", "∩": "\\cap", "≤": "\\le", "≥": "\\ge",
    "≠": "\\ne", "→": "\\to", "←": "\\leftarrow", "↦": "\\mapsto", "⇒": "\\Rightarrow",
    "⇐": "\\Leftarrow", "⇔": "\\Leftrightarrow", "↔": "\\leftrightarrow", "⟶": "\\longrightarrow",
    "∀": "\\forall", "∃": "\\exists", "∄": "\\nexists", "∞": "\\infty", "⋅": "\\cdot", "·": "\\cdot",
    "×": "\\times", "÷": "\\div", "±": "\\pm", "∓": "\\mp", "∑": "\\sum", "∏": "\\prod",
    "∫": "\\int", "∮": "\\oint", "∂": "\\partial", "∇": "\\nabla", "□": "\\square",
    "∎": "\\blacksquare", "∅": "\\emptyset", "≈": "\\approx", "≡": "\\equiv", "≅": "\\cong",
    "∼": "\\sim", "∝": "\\propto", "⊥": "\\perp", "∥": "\\Vert", "∣": "|", "⟨": "\\langle",
    "⟩": "\\rangle", "…": "\\ldots", "⋯": "\\cdots", "⋮": "\\vdots", "⋱": "\\ddots",
    "¬": "\\neg", "∧": "\\wedge", "∨": "\\vee", "⊕": "\\oplus", "⊗": "\\otimes",
    "ℵ": "\\aleph", "ℓ": "\\ell", "ℏ": "\\hbar", "−": "-", "′": "'", "″": "''",
    "{": "\\{", "}": "\\}", "#": "\\#", "%": "\\%", "&": "\\&", "$": "\\$", "_": "\\_",
    "α": "\\alpha", "β": "\\beta", "γ": "\\gamma", "δ": "\\delta", "ε": "\\varepsilon",
    "ϵ": "\\epsilon", "ζ": "\\zeta", "η": "\\eta", "θ": "\\theta", "ϑ": "\\vartheta",
    "ι": "\\iota", "κ": "\\kappa", "λ": "\\lambda", "μ": "\\mu", "ν": "\\nu", "ξ": "\\xi",
    "π": "\\pi", "ρ": "\\rho", "σ": "\\sigma", "τ": "\\tau", "υ": "\\upsilon", "φ": "\\varphi",
    "ϕ": "\\phi", "χ": "\\chi", "ψ": "\\psi", "ω": "\\omega", "Γ": "\\Gamma", "Δ": "\\Delta",
    "Θ": "\\Theta", "Λ": "\\Lambda", "Ξ": "\\Xi", "Π": "\\Pi", "Σ": "\\Sigma", "Υ": "\\Upsilon",
    "Φ": "\\Phi", "Ψ": "\\Psi", "Ω": "\\Omega", "ℝ": "\\mathbb{R}", "ℕ": "\\mathbb{N}",
    "ℤ": "\\mathbb{Z}", "ℚ": "\\mathbb{Q}", "ℂ": "\\mathbb{C}",
    "\u2061": "", "\u2062": "", "\u2063": "", "\u2064": "", "\u200b": "",
  };
  const FUNCTION_NAMES = new Set(["sin", "cos", "tan", "cot", "sec", "csc", "log", "ln", "exp",
    "lim", "max", "min", "sup", "inf", "det", "dim", "ker", "deg", "gcd", "arg", "sinh", "cosh",
    "tanh", "arcsin", "arccos", "arctan", "Pr", "hom", "liminf", "limsup"]);

  /** Accent characters as MathML writes them, and the command each one means. */
  const ACCENTS = {
    "→": "\\vec", "⃗": "\\vec", "¯": "\\overline", "‾": "\\overline", "ˉ": "\\bar",
    "^": "\\hat", "ˆ": "\\hat", "~": "\\tilde", "˜": "\\tilde", "˙": "\\dot", "¨": "\\ddot",
    "⏞": "\\overbrace", "⏟": "\\underbrace", "_": "\\underline",
  };
  /** The same accents on a letter of prose: "u" + "¨" is simply "ü". */
  const COMBINING = { "¨": "̈", "´": "́", "`": "̀", "^": "̂", "ˆ": "̂",
    "~": "̃", "˜": "̃", "˚": "̊", "¸": "̧" };

  function tokenLatex(text) {
    let out = "";
    for (const ch of text) {
      const mapped = MO_LATEX[ch];
      if (mapped !== undefined) {
        // A letter right after a command would become part of its name.
        out += /^\\[a-zA-Z]+$/.test(mapped) ? `${mapped} ` : mapped;
      } else {
        out += normalizeMathChars(ch);
      }
    }
    return out;
  }

  const braced = (latex) => `{${latex.trim()}}`;
  const group = (latex) => {
    const t = latex.trim();
    return t.length === 1 ? t : braced(t);
  };

  const MATRIX_FENCES = { "(": "pmatrix", "[": "bmatrix", "|": "vmatrix", "∣": "vmatrix",
    "∥": "Vmatrix", "‖": "Vmatrix" };
  const moText = (el) => (el && el.localName === "mo" ? el.textContent.trim() : null);

  /** Sibling patterns that stand for one LaTeX construct. */
  function rowLatex(kids) {
    const first = moText(kids[0]);
    const last = moText(kids[kids.length - 1]);
    const middle = kids.length === 3 ? kids[1] : null;

    if (kids.length >= 2 && kids[1]?.localName === "mtable" && kids.length <= 3) {
      const body = tableBody(kids[1]);
      if (first === "{" && (kids.length === 2 || last === "")) return `\\begin{cases}${body}\\end{cases}`;
      if (first === "{" && last === "}") return `\\begin{Bmatrix}${body}\\end{Bmatrix}`;
      if (MATRIX_FENCES[first]) return `\\begin{${MATRIX_FENCES[first]}}${body}\\end{${MATRIX_FENCES[first]}}`;
    }
    if (middle && middle.localName === "mfrac" && first === "(" && last === ")"
        && /^0(px|em|pt)?$/.test(middle.getAttribute("linethickness") || "")) {
      const [top, bottom] = [...middle.children];
      return `\\binom{${mathmlToLatex(top)}}{${mathmlToLatex(bottom)}}`;
    }
    return null;
  }

  function tableBody(mtable) {
    return [...mtable.children]
      .map((tr) => [...tr.children].map((td) => mathmlToLatex(td).trim()).join("&"))
      .join("\\\\");
  }

  /* Neighbouring prose pieces are one \text{}: "f", "ü", "r alle " → "für alle ". */
  const mergeText = (latex) => {
    let before;
    do {
      before = latex;
      latex = latex.replace(/\\text\{((?:[^{}\\]|\\.)*)\}\\text\{((?:[^{}\\]|\\.)*)\}/g, "\\text{$1$2}");
    } while (latex !== before);
    return latex;
  };

  function mathmlToLatex(node) {
    if (!node) return "";
    if (node.nodeType === Node.TEXT_NODE) return tokenLatex(node.textContent.trim());
    if (node.nodeType !== Node.ELEMENT_NODE) return "";
    const name = node.localName;
    const kids = [...node.children];
    const all = () => mergeText(rowLatex(kids) ?? kids.map(mathmlToLatex).join(""));

    switch (name) {
      case "math":
      case "mrow":
      case "mstyle":
      case "mpadded":
      case "mphantom":
      case "mtd":
        return all();
      case "semantics": {
        const tex = node.querySelector('annotation[encoding="application/x-tex"], annotation[encoding="TeX"]');
        return tex ? unwrapDisplaystyle(tex.textContent) : mathmlToLatex(kids[0]);
      }
      case "annotation":
      case "annotation-xml":
        return "";
      case "mi": {
        const text = node.textContent.trim();
        if (FUNCTION_NAMES.has(text)) return `\\${text} `;
        if (node.getAttribute("mathvariant") === "double-struck" && /^[A-Za-z]$/.test(text)) return `\\mathbb{${text}}`;
        if (node.getAttribute("mathvariant") === "fraktur" && /^[A-Za-z]$/.test(text)) return `\\mathfrak{${text}}`;
        if (node.getAttribute("mathvariant") === "script" && /^[A-Za-z]$/.test(text)) return `\\mathcal{${text}}`;
        if ([...text].length > 1 && /^[A-Za-z]+$/.test(text)) return `\\operatorname{${text}}`;
        return tokenLatex(text);
      }
      case "mn":
      case "mo":
        return tokenLatex(node.textContent.trim());
      case "mtext":
      case "ms": {
        const raw = node.textContent;
        if (!raw.replace(/[\s\u00a0\u2061-\u2064\u200b]/g, "")) return /[\u2009\u2006]/.test(raw) ? "\\," : /[ \u00a0]/.test(raw) ? "\\ " : "";
        return `\\text{${escapeTextLatex(raw.replace(/\u00a0/g, " "))}}`;
      }
      case "mspace": {
        const width = parseFloat(node.getAttribute("width") || "0");
        if (width >= 1.9) return "\\qquad ";
        if (width >= 0.9) return "\\quad ";
        if (width >= 0.25) return "\\;";
        if (width >= 0.15) return "\\,";
        return "";
      }
      case "msub":
        return `${mathmlToLatex(kids[0])}_${group(mathmlToLatex(kids[1]))}`;
      case "msup": {
        const sup = moText(kids[1]);
        if (sup === "′" || sup === "″" || sup === "'") return `${mathmlToLatex(kids[0])}${tokenLatex(sup)}`;
        return `${mathmlToLatex(kids[0])}^${group(mathmlToLatex(kids[1]))}`;
      }
      case "msubsup":
        return `${mathmlToLatex(kids[0])}_${group(mathmlToLatex(kids[1]))}^${group(mathmlToLatex(kids[2]))}`;
      case "mover":
      case "munder": {
        const mark = kids[1]?.textContent.trim();
        const base = kids[0];
        if (base?.localName === "mtext" && COMBINING[mark]) {
          return `\\text{${escapeTextLatex((base.textContent + COMBINING[mark]).normalize("NFC"))}}`;
        }
        if (ACCENTS[mark] && (node.getAttribute("accent") === "true" || node.getAttribute("accentunder") === "true" || mark === "¯" || mark === "→")) {
          const cmd = name === "munder" && mark === "_" ? "\\underline" : ACCENTS[mark];
          return `${cmd}${braced(mathmlToLatex(base))}`;
        }
        return `${mathmlToLatex(base)}${name === "mover" ? "^" : "_"}${group(mathmlToLatex(kids[1]))}`;
      }
      case "munderover":
        return `${mathmlToLatex(kids[0])}_${group(mathmlToLatex(kids[1]))}^${group(mathmlToLatex(kids[2]))}`;
      case "mfrac":
        return `\\frac{${mathmlToLatex(kids[0])}}{${mathmlToLatex(kids[1])}}`;
      case "msqrt":
        return `\\sqrt{${all()}}`;
      case "mroot":
        return `\\sqrt[${mathmlToLatex(kids[1])}]{${mathmlToLatex(kids[0])}}`;
      case "mfenced": {
        const open = node.getAttribute("open") ?? "(";
        const close = node.getAttribute("close") ?? ")";
        return `${tokenLatex(open)}${kids.map(mathmlToLatex).join(",")}${tokenLatex(close)}`;
      }
      case "menclose":
        return `\\boxed{${all()}}`;
      case "mtable":
        return `\\begin{matrix}${tableBody(node)}\\end{matrix}`;
      default:
        return all() || tokenLatex(node.textContent.trim());
    }
  }

  // ------------------------------------------------------------ HTML

  const BLOCK_TAGS = new Set(["P", "DIV", "SECTION", "ARTICLE", "BLOCKQUOTE", "UL", "OL", "PRE",
    "HEADER", "FOOTER", "MAIN", "ASIDE", "FIGURE", "DL", "DT", "DD", "HR", "TBODY", "THEAD"]);
  const SKIP_TAGS = new Set(["SCRIPT", "STYLE", "HEAD", "TITLE", "META", "LINK", "NOSCRIPT",
    "TEMPLATE", "SVG", "BUTTON", "IMG", "ANNOTATION"]);

  /** The TeX a rendered formula carries, or `null` if it carries none. */
  function texOf(element) {
    const annotation = element.querySelector(
      'annotation[encoding="application/x-tex"], annotation[encoding="TeX"], annotation[encoding="application/x-latex"]');
    if (annotation && annotation.textContent.trim()) return unwrapDisplaystyle(annotation.textContent);
    const math = element.localName === "math" ? element : element.querySelector("math");
    const alt = math?.getAttribute("alttext");
    if (alt && alt.trim()) return unwrapDisplaystyle(alt);
    if (math) return mathmlToLatex(math);
    return null;
  }

  function parseHTML(html) {
    const doc = new DOMParser().parseFromString(html, "text/html");
    const paragraphs = [];
    let line = { type: "line", heading: false, runs: [] };

    const flush = () => {
      const runs = tidyRuns(line.runs);
      if (runs.length) paragraphs.push({ type: "line", heading: line.heading, runs });
      line = { type: "line", heading: false, runs: [] };
    };

    const pushMath = (latex, display) => {
      if (!latex || !latex.trim()) return;
      if (display) {
        flush();
        paragraphs.push({ type: "display", latex: latex.trim() });
      } else {
        line.runs.push(mathRun(latex));
      }
    };

    function walk(node, style) {
      if (node.nodeType === Node.TEXT_NODE) {
        const text = node.textContent.replace(/\s+/g, " ");
        if (text) line.runs.push(textRun(text, style));
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      const el = node;
      const tag = el.tagName.toUpperCase();
      const cls = el.classList;

      if (SKIP_TAGS.has(tag)) return;

      // ---- formulas
      if (cls.contains("katex-display")) {
        pushMath(texOf(el), true);
        return;
      }
      if (cls.contains("katex") || cls.contains("katex-mathml")) {
        pushMath(texOf(el), false);
        return;
      }
      if (tag === "MJX-CONTAINER") {
        pushMath(texOf(el), el.getAttribute("display") === "true");
        return;
      }
      if (tag === "SCRIPT" && /math\/tex/.test(el.getAttribute("type") || "")) {
        pushMath(el.textContent, /mode=display/.test(el.getAttribute("type")));
        return;
      }
      if (cls.contains("mwe-math-element")) {
        const math = el.querySelector("math");
        pushMath(texOf(el), math?.getAttribute("display") === "block");
        return;
      }
      if (tag === "MATH") {
        pushMath(texOf(el), el.getAttribute("display") === "block");
        return;
      }

      // ---- structure
      if (tag === "BR") {
        flush();
        return;
      }
      if (tag === "TABLE") {
        flush();
        const table = parseTable(el);
        if (table) paragraphs.push(table);
        return;
      }
      if (/^H[1-6]$/.test(tag)) {
        flush();
        line.heading = true;
        for (const child of el.childNodes) walk(child, style);
        flush();
        return;
      }
      if (tag === "LI") {
        flush();
        line.runs.push(textRun("• ", style));
        for (const child of el.childNodes) walk(child, style);
        flush();
        return;
      }

      const next = { ...style };
      if (tag === "B" || tag === "STRONG") next.bold = true;
      if (tag === "I" || tag === "EM") next.italic = true;
      const weight = el.style?.fontWeight;
      if (weight === "bold" || Number(weight) >= 600) next.bold = true;
      if (el.style?.fontStyle === "italic") next.italic = true;

      const block = BLOCK_TAGS.has(tag);
      if (block) flush();
      for (const child of el.childNodes) walk(child, next);
      if (block) flush();
    }

    function parseTable(table) {
      const rows = [];
      let header = false;
      for (const tr of table.querySelectorAll("tr")) {
        if (tr.closest("table") !== table) continue;
        const cells = [...tr.children].filter((c) => c.tagName === "TD" || c.tagName === "TH");
        if (!cells.length) continue;
        if (rows.length === 0 && cells.every((c) => c.tagName === "TH")) header = true;
        rows.push(cells.map((cell) => {
          const inner = parseHTML(cell.innerHTML);
          // A cell is one line; several paragraphs in it are joined by spaces.
          const runs = [];
          inner.forEach((p, i) => {
            if (i > 0) runs.push(textRun(" "));
            if (p.type === "display") runs.push(mathRun(p.latex));
            else if (p.type === "line") runs.push(...p.runs);
          });
          return tidyRuns(runs);
        }));
      }
      if (!rows.length) return null;
      const width = Math.max(...rows.map((r) => r.length));
      for (const row of rows) while (row.length < width) row.push([]);
      return { type: "table", header, rows };
    }

    walk(doc.body, { bold: false, italic: false });
    flush();
    return paragraphs;
  }

  // ------------------------------------------------------------ plain text

  /* Rendered KaTeX copied as plain text comes out twice: first the MathML
     reading, one symbol per line ("𝑥\n1\n,\n𝑥\n2"), then the visible HTML
     ("x \n1\n\u200b\n ,x \n2\n\u200b"). The first has the symbols in order, the
     second shows where scripts were: a script sits on its own line, and a
     subscript is followed by a zero-width space (Chrome) or a tab (Safari). */

  const TOKEN_LINE = /^(?:[\u{1d400}-\u{1d7ff}ℎ]|[A-Za-z]|\d+|[+\-−=<>≤≥≠∘∈∉⊂⊆∪∩→←↦⇒⇔∀∃∞⋅·×±∑∏∫∂∇□∎∅≈≡∣|/()[\]{},.;:!′'⟨⟩…⋯¬∧∨]|[Ͱ-Ͽ]|[ℝℕℤℚℂ])$/u;

  const squash = (text) => text.replace(/[\s\u200b]/g, "");

  const sortedChars = (text) => [...squash(text)].sort().join("");
  const isMarkerLine = (line) => /[\u200b\t]/.test(line) && /^[\s\u200b]*$/.test(line);

  /* Looks for the displayed echo of `wanted` starting at line `k`. Fractions are
     displayed denominator first, so the echo is compared as a multiset of
     characters, not as a sequence. */
  function matchEcho(lines, k, wanted, exact) {
    const target = squash(wanted);
    const echo = [];
    let count = 0;
    let rest = "";
    while (k < lines.length && count < target.length) {
      const line = lines[k];
      let cut = line.length;
      for (let c = 0; c < line.length; c += 1) {
        if (/[\s\u200b]/.test(line[c])) continue;
        count += 1;
        if (count === target.length) { cut = c + 1; break; }
      }
      echo.push(line.slice(0, cut));
      k += 1;
      if (cut < line.length) {
        rest = line.slice(cut);
        break;
      }
    }
    if (count !== target.length) return null;
    const shown = squash(echo.join(""));
    if (exact ? shown !== target : sortedChars(shown) !== sortedChars(target)) return null;

    if (!rest.trim()) {
      // The echo ended with its line: swallow the marker that closes a trailing
      // subscript (plus the empty line Safari adds), and take the line after it
      // as the rest of the sentence when KaTeX indented it.
      let marked = false;
      let chrome = false;
      if (rest && isMarkerLine(rest)) { echo.push(rest); chrome = rest.includes("\u200b"); rest = ""; marked = true; }
      while (k < lines.length && isMarkerLine(lines[k])) {
        chrome = chrome || lines[k].includes("\u200b");
        echo.push(lines[k]);
        k += 1;
        marked = true;
      }
      if (marked && k < lines.length && lines[k] === "" && k + 1 < lines.length && lines[k + 1] !== "") k += 1;
      // Chrome also leaves a blank after the base of a script ("a \n2").
      chrome = chrome || echo.some((line) => / $/.test(line));
      const indented = k < lines.length && /^\s/.test(lines[k]) && echo.length > 1;
      if ((marked || indented) && k < lines.length && lines[k] !== "" && !TOKEN_LINE.test(lines[k])) {
        // Chrome indents the line after a script by one blank that is not text.
        rest = chrome ? lines[k].replace(/^ /, "") : lines[k];
        k += 1;
      }
    }
    return { k, echo, rest };
  }

  function repairRenderedKatex(text) {
    const lines = text.split("\n");
    const out = [];
    let i = 0;

    while (i < lines.length) {
      let j = i;
      while (j < lines.length && TOKEN_LINE.test(lines[j])) j += 1;
      const run = lines.slice(i, j);
      const isFormula = run.length > 0
        && run.some((t) => MATH_ALNUM.test(t) || /[∘∈∉⊂⊆∪∩→↦⇒⇔∀∃∞∑∏∫∂∇□∎]/u.test(t));

      if (!isFormula) {
        out.push({ kind: "text", text: lines[i] });
        i += 1;
        continue;
      }

      // The echo may start inside the run of symbol lines ("□\n□"), so every
      // split is tried, shortest formula first.
      let found = null;
      for (const exact of [true, false]) {
        for (let end = i + 1; end <= j && !found; end += 1) {
          const tokens = lines.slice(i, end);
          const wanted = tokens.map((t) => normalizeMathChars(t).replace(/\\mathbb\{(.)\}/g, "$1")).join("");
          const match = matchEcho(lines, end, wanted, exact);
          if (match) found = { tokens, match };
        }
        if (found) break;
      }

      if (!found) {
        out.push({ kind: "text", text: run.map((t) => normalizeMathChars(t)).join("") });
        i = j;
        continue;
      }
      out.push({ kind: "math", latex: latexFromEcho(found.tokens, found.match.echo), rest: found.match.rest });
      i = found.match.k;
    }

    // Re-assemble: a formula continues the line before it unless that line was
    // empty, and whatever followed the echo continues after it.
    const paragraphs = [];
    let current = null;
    const startLine = () => {
      current = { type: "line", heading: false, runs: [] };
      paragraphs.push(current);
    };
    for (let n = 0; n < out.length; n += 1) {
      const piece = out[n];
      if (piece.kind === "text") {
        if (piece.text.trim() === "") {
          current = null;
          continue;
        }
        const previous = out[n - 1];
        const joins = previous && previous.kind === "math" && !previous.rest && current;
        if (!joins) startLine();
        current.runs.push(...inlineMarkdown(piece.text));
      } else {
        if (!current) startLine();
        current.runs.push(mathRun(piece.latex));
        if (piece.rest) current.runs.push(...inlineMarkdown(piece.rest));
        // The text line after an echo belongs to a new line unless the echo
        // ended mid-line (then `rest` carried it).
        if (!piece.rest) {
          const next = out[n + 1];
          if (next && next.kind === "text" && next.text.trim() !== "") current = null;
        }
      }
    }
    return paragraphs
      .map((p) => ({ ...p, runs: tidyRuns(p.runs) }))
      .filter((p) => p.runs.length)
      .map((p) => (p.runs.every((r) => r.t === "math") ? { type: "display", latex: runsToLatex(p.runs) } : p));
  }

  /** Rebuilds sub- and superscripts from the displayed echo of a formula.

      In the echo the baseline stays on one line and every script sits on a line
      of its own, so lines alternate: base, script, base, script … A subscript
      is followed by a marker line (zero-width space or tab); a line with both
      scripts shows the subscript first, then the superscript, then the marker. */
  function latexFromEcho(tokens, echo) {
    const plain = tokens.map((t) => tokenLatex(t)).join("").trim();
    const items = [];
    for (const line of echo) {
      if (isMarkerLine(line)) {
        if (items.length) items[items.length - 1].marked = true;
        continue;
      }
      const text = line.replace(/[\s\u00a0\u200b]+/g, "");
      if (text) items.push({ text, marked: false });
    }
    if (items.length <= 1) return plain;

    const tex = (item) => tokenLatex(item.text).trim();
    const script = (item) => {
      const body = tex(item);
      return [...body].length === 1 ? body : `{${body}}`;
    };

    let latex = tex(items[0]);
    let i = 1;
    while (i < items.length) {
      const first = items[i];
      const second = items[i + 1];
      if (!first.marked && second && second.marked) {
        latex += `_${script(first)}^${script(second)}`;
        i += 2;
      } else if (first.marked) {
        latex += `_${script(first)}`;
        i += 1;
      } else {
        latex += `^${script(first)}`;
        i += 1;
      }
      if (i < items.length) {
        latex += tex(items[i]);
        i += 1;
      }
    }

    // Only trust the rebuild if it kept every symbol; a flat formula is still
    // better than a wrong one.
    const symbols = (t) => squash(t.replace(/[_^{}]/g, "").replace(/\\[a-zA-Z]+/g, "#"));
    return symbols(latex) === symbols(plain) ? latex : plain;
  }

  /** **bold**, *italic* and $…$ / \(…\) inside one line of plain text. */
  function inlineMarkdown(text) {
    const runs = [];
    const pattern = /\$\$([\s\S]+?)\$\$|\$(?!\s)([^$\n]+?)(?<!\s)\$|\\\(([\s\S]+?)\\\)|\\\[([\s\S]+?)\\\]|\*\*([^*\n]+)\*\*|(?<![*\w])\*(?!\s)([^*\n]+?)(?<!\s)\*(?!\w)/g;
    let last = 0;
    for (const match of text.matchAll(pattern)) {
      if (match.index > last) runs.push(textRun(text.slice(last, match.index)));
      const [, dd, d, paren, bracket, bold, italic] = match;
      if (dd !== undefined) runs.push(mathRun(dd));
      else if (d !== undefined) {
        // "5$ und 10$" is money, not maths.
        if (/^\d+([.,]\d+)?\s/.test(d) && /\s$/.test(text.slice(0, match.index))) runs.push(textRun(match[0]));
        else runs.push(mathRun(d));
      } else if (paren !== undefined) runs.push(mathRun(paren));
      else if (bracket !== undefined) runs.push(mathRun(bracket));
      else if (bold !== undefined) runs.push(textRun(bold, { bold: true }));
      else if (italic !== undefined) runs.push(textRun(italic, { italic: true }));
      last = match.index + match[0].length;
    }
    if (last < text.length) runs.push(textRun(text.slice(last)));
    return runs;
  }

  function parsePlain(text) {
    text = text.replace(/\r\n?/g, "\n");
    if (MATH_ALNUM.test(text)) return repairRenderedKatex(text);

    const paragraphs = [];
    // Display maths may span lines; take it out first.
    const pieces = text.split(/(\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\])/);
    for (const piece of pieces) {
      const display = /^\$\$([\s\S]+)\$\$$/.exec(piece) || /^\\\[([\s\S]+)\\\]$/.exec(piece);
      if (display) {
        paragraphs.push({ type: "display", latex: display[1].trim() });
        continue;
      }
      for (const raw of piece.split("\n")) {
        if (!raw.trim()) continue;
        const heading = /^\s{0,3}#{1,6}\s+(.*)$/.exec(raw);
        const bullet = /^\s*[-*•]\s+(.*)$/.exec(raw);
        const body = heading ? heading[1] : bullet ? `• ${bullet[1]}` : raw;
        const runs = tidyRuns(inlineMarkdown(body));
        if (!runs.length) continue;
        paragraphs.push({ type: "line", heading: Boolean(heading), runs });
      }
    }
    return paragraphs;
  }

  // ------------------------------------------------------------ entry point

  /** Clipboard contents as paragraphs. HTML wins when it carries formulas. */
  function parseClipboard(html, plain) {
    if (html && html.trim()) {
      const fromHTML = parseHTML(html);
      if (hasMath(fromHTML) || !plain || !hasMath(parsePlain(plain))) {
        if (fromHTML.length) return fromHTML;
      }
    }
    return plain ? parsePlain(plain) : [];
  }

  /** Paragraphs as sheet lines: {kind, value}. */
  function toBlocks(paragraphs) {
    const blocks = [];
    for (const p of paragraphs) {
      if (p.type === "display") {
        blocks.push({ kind: "math", value: p.latex });
      } else if (p.type === "table") {
        const rows = p.rows.map((row) => row.map(runsToLatex));
        blocks.push({
          kind: "table",
          value: JSON.stringify({
            rows,
            header: p.header,
            style: "grid",
            align: rows[0].map(() => "left"),
            widths: rows[0].map(() => null),
          }),
        });
      } else if (p.runs.some((r) => r.t === "math")) {
        const textual = p.runs.some((r) => r.t === "text" && r.text.trim());
        blocks.push({ kind: textual ? "mixed" : "math", value: runsToLatex(p.runs) });
      } else {
        blocks.push({ kind: p.heading ? "heading" : "paragraph", value: runsToHTML(p.runs) });
      }
    }
    return blocks;
  }

  window.MathPaste = {
    parseClipboard,
    parseHTML,
    parsePlain,
    toBlocks,
    runsToLatex,
    tidyRuns,
    hasMath,
    mathmlToLatex,
    escapeTextLatex,
  };
})();
