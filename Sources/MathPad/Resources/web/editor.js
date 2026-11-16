/* MathPad — sheet editor.
 *
 * The whole sheet lives in one web view: a vertical list of blocks, each either
 * a MathLive field (LaTeX under the hood), a LaTeX source textarea, or prose.
 * Swift owns persistence, menus and the symbol palette and talks to this file
 * through `window.MP`; this file reports back through `Bridge.post`.
 */

(() => {
  "use strict";

  // ---------------------------------------------------------------- bridge

  const Bridge = {
    post(name, payload) {
      try {
        window.webkit.messageHandlers.mathpad.postMessage({ name, payload });
      } catch (_) {
        /* running outside the app (e.g. plain browser) — ignore */
      }
    },
  };

  window.addEventListener("error", (e) => {
    Bridge.post("log", { text: `JS-Fehler: ${e.message} @ ${e.filename}:${e.lineno}` });
  });

  /** @type {{id: string, kind: string, value: string}[]} */
  let blocks = [];
  /** ids currently displayed as raw LaTeX instead of rendered math */
  const sourceMode = new Set();
  let focusedID = null;
  /** The cell the caret is in when the focused line is a table: {id, r, c}. */
  let activeCell = null;
  let changeTimer = null;
  let loading = false;

  // ---------------------------------------------------------------- rich text

  /* Prose blocks store HTML so a note can be bold, coloured or highlighted.
     Only the handful of tags and style properties WebKit's editing commands
     produce survive; everything else is unwrapped to plain text, so a paste
     from a web page cannot smuggle markup into a sheet. */
  const ALLOWED_TAGS = new Set(["B", "STRONG", "I", "EM", "U", "SPAN", "BR"]);
  const ALLOWED_STYLES = [
    "color",
    "background-color",
    "font-weight",
    "font-style",
    "text-decoration-line",
    "text-decoration",
  ];

  function sanitizeHTML(html) {
    // DOMParser never runs scripts or loads resources, unlike innerHTML on a
    // live element.
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html");
    scrub(doc.body);
    return doc.body.innerHTML;
  }

  function scrub(node) {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.TEXT_NODE) continue;
      if (child.nodeType !== Node.ELEMENT_NODE) {
        child.remove();
        continue;
      }
      if (!ALLOWED_TAGS.has(child.tagName)) {
        while (child.firstChild) node.insertBefore(child.firstChild, child);
        child.remove();
        continue;
      }
      const keep = child.tagName === "SPAN" ? keptStyle(child) : "";
      for (const attribute of [...child.attributes]) child.removeAttribute(attribute.name);
      if (keep) child.setAttribute("style", keep);
      scrub(child);
    }
  }

  function keptStyle(element) {
    return ALLOWED_STYLES
      .map((property) => {
        const value = element.style.getPropertyValue(property);
        return value ? `${property}:${value};` : "";
      })
      .join("");
  }

  /** Text without markup — used for the "is this line empty" check. */
  function plainText(html) {
    if (!looksLikeMarkup(html)) return html;
    const doc = new DOMParser().parseFromString(`<body>${html}</body>`, "text/html");
    return doc.body.textContent || "";
  }

  /* A stored note is HTML — but sheets written before formatting existed, and
     lines coming straight out of worksheet recognition, hold plain text. Text
     that contains neither a tag nor an entity is set verbatim, so a lone "<"
     stays a "<" instead of being read as the start of a tag. */
  const looksLikeMarkup = (value) => value.includes("<") || value.includes("&");

  function setProseContent(element, value) {
    if (looksLikeMarkup(value)) element.innerHTML = sanitizeHTML(value);
    else element.textContent = value;
  }

  // ---------------------------------------------------------------- state

  const sheetEl = () => document.getElementById("sheet");
  const rowOf = (id) => document.querySelector(`.block[data-id="${id}"]`);
  const indexOf = (id) => blocks.findIndex((b) => b.id === id);
  const uid = () =>
    (crypto.randomUUID ? crypto.randomUUID() : String(Math.random())).toUpperCase();

  function scheduleChange() {
    if (loading) return;
    clearTimeout(changeTimer);
    changeTimer = setTimeout(() => {
      Bridge.post("change", { blocks });
    }, 200);
  }

  function reportFocus() {
    const block = blocks[indexOf(focusedID)];
    Bridge.post("focus", {
      id: focusedID,
      kind: block ? block.kind : null,
      source: sourceMode.has(focusedID),
      table: block && block.kind === "table" ? tableFocus(block) : null,
    });
  }

  // ---------------------------------------------------------------- history

  /* One undo stack for the whole sheet rather than one per field.
     MathLive and contenteditable each bring their own, but neither can undo
     "I deleted a line" or "I switched this line to a formula" — and two
     competing stacks is worse than one. ⌘Z is therefore caught before MathLive
     sees it, and restores a whole-document snapshot. */
  const history = { past: [], future: [], lastPush: 0, limit: 200 };
  let historySuspended = false;

  const snapshot = () => ({
    blocks: blocks.map((block) => ({ ...block })),
    focus: focusedID,
    cell: activeCell ? { ...activeCell } : null,
  });

  const sameBlocks = (a, b) =>
    a.length === b.length &&
    a.every((block, i) => block.id === b[i].id
      && block.kind === b[i].kind
      && block.value === b[i].value);

  /** Records the state *before* a change. `coalesce` groups a burst of typing. */
  function pushHistory(coalesce = false) {
    if (historySuspended || loading) return;
    const now = Date.now();
    const current = snapshot();
    const top = history.past[history.past.length - 1];
    if (top && sameBlocks(top.blocks, current.blocks)) return;
    if (coalesce && now - history.lastPush < 700) return;

    history.past.push(current);
    if (history.past.length > history.limit) history.past.shift();
    history.future.length = 0;
    history.lastPush = now;
  }

  function restore(entry) {
    blocks = entry.blocks.map((block) => ({ ...block }));
    renderAll(entry.focus, entry.cell);
    scheduleChange();
  }

  function undo() {
    if (!history.past.length) return false;
    history.future.push(snapshot());
    restore(history.past.pop());
    history.lastPush = 0;
    return true;
  }

  function redo() {
    if (!history.future.length) return false;
    history.past.push(snapshot());
    restore(history.future.pop());
    history.lastPush = 0;
    return true;
  }

  /** Rebuilds every row from `blocks` and puts the caret back. */
  function renderAll(focusID, cell = null) {
    blurFields(sheetEl());
    sourceMode.clear();
    focusedID = null;
    activeCell = null;
    sheetEl().replaceChildren(...blocks.map(buildRow));
    const target = focusID && indexOf(focusID) >= 0 ? focusID : blocks[0]?.id;
    if (!target) return;
    if (cell && cell.id === target && blocks[indexOf(target)].kind === "table") {
      focusCell(target, cell.r, cell.c, "end");
    } else {
      focusBlock(target, "end");
    }
  }

  /** MathLive throws if a focused field is taken out of the page mid-focus. */
  function blurFields(root) {
    if (document.activeElement && document.activeElement !== document.body) {
      try { document.activeElement.blur(); } catch (_) { /* already gone */ }
    }
    for (const field of root.querySelectorAll("math-field")) {
      try { field.blur(); } catch (_) { /* already gone */ }
    }
  }

  // ---------------------------------------------------------------- converting

  /* A line stores LaTeX when it is a formula and HTML when it is prose, so
     changing its kind has to change the value with it. Handing one format to the
     other renderer is what used to happen: a fraction turned into the literal
     text "\frac{a}{b}", and a styled note arrived in MathLive as raw <span>. */

  let scratch = null;

  /** Reads LaTeX the way a person would say it: "\frac{a}{b}" → "(a)/(b)". */
  function latexToPlainText(latex) {
    if (!latex) return "";
    if (!scratch) {
      scratch = document.createElement("math-field");
      scratch.style.cssText = "position:absolute;left:-9999px;top:0;width:1px;height:1px;";
      scratch.mathVirtualKeyboardPolicy = "manual";
      document.body.appendChild(scratch);
    }
    try {
      scratch.value = latex;
      return scratch.getValue("plain-text");
    } catch (_) {
      return latex;
    }
  }

  function escapeHTML(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // Blanks do not count: "x > 0" typed as prose reads back from a formula as "x>0".
  const sameText = (a, b) => a.replace(/\s+/g, "") === b.replace(/\s+/g, "");

  /** The value `block` should hold once it is of kind `to`. */
  function convertedValue(block, to) {
    const fromProse = isProse(block.kind);
    const toProse = isProse(to);
    if (fromProse === toProse) return block.value;

    /* Switching back and forth should not grind the content down. The previous
       representation is kept, and if nothing was edited in between it is simply
       put back — so formula → text → formula returns the original fraction
       rather than the "(a)/(b)" reading of it. */
    const stashed = block.alt;
    if (stashed && isProse(stashed.kind) === toProse) {
      const now = fromProse ? plainText(block.value) : latexToPlainText(block.value);
      const then = toProse ? plainText(stashed.value) : latexToPlainText(stashed.value);
      if (sameText(now, then)) return stashed.value;
    }

    if (toProse) return escapeHTML(latexToPlainText(block.value));

    const words = plainText(block.value);
    // A mixed line reads the sentence the way typing it would have: words stay
    // words, "x > 0" becomes a formula. The right-click menu fixes the rest.
    if (to === "mixed") {
      if (!words.trim()) return "";
      return window.MathPaste.runsToLatex(window.MathPaste.tidyRuns(window.MixedInput.classifyPlain(words)));
    }

    /* A formula line reads the text as maths. The plain-text form produced going
       the other way is AsciiMath, so converting it back is very nearly the exact
       inverse: "(a)/(b)" becomes a fraction again and "sqrt(x)" a root, even
       after the text was edited in between. */
    if (words.includes("\\")) return words; // already written as LaTeX
    try {
      const tex = window.MathLive?.convertAsciiMathToLatex?.(words);
      if (tex && tex.trim()) return tex.trim();
    } catch (_) { /* fall back to the raw text below */ }
    return words;
  }

  // ---------------------------------------------------------------- MathLive

  const ready = customElements.whenDefined("math-field");

  if (window.MathfieldElement) {
    MathfieldElement.fontsDirectory = "fonts"; // resolved relative to mathlive.min.js
    MathfieldElement.soundsDirectory = null;
    MathfieldElement.keypressVibration = false;
  }

  /** Typed abbreviations that expand while you write. */
  const EXTRA_SHORTCUTS = {
    // German words, so you can think in German while typing
    wurzel: "\\sqrt{#0}",
    bruch: "\\frac{#0}{#?}",
    summe: "\\sum_{#?}^{#?}",
    integral: "\\int_{#?}^{#?}",
    unendlich: "\\infty",
    grenzwert: "\\lim_{#? \\to #?}",
    matrix: "\\begin{pmatrix}#0&#?\\\\#?&#?\\end{pmatrix}",
    faelle: "\\begin{cases}#0&#?\\\\#?&#?\\end{cases}",
    // common notation people expect to "just work"
    "=>": "\\implies",
    "<=>": "\\iff",
    "|->": "\\mapsto",
    "...": "\\ldots",
    // MathLive's own defaults for these two render as error boxes.
    "//": "/",
    "R^n": "\\mathbb{R}^n",
    NN: "\\mathbb{N}",
    ZZ: "\\mathbb{Z}",
    QQ: "\\mathbb{Q}",
    RR: "\\mathbb{R}",
    CC: "\\mathbb{C}",
    dd: "\\mathrm{d}",
  };

  /// Must run only after the element has been upgraded and mounted: before that
  /// `mf.inlineShortcuts` is undefined, and spreading it would silently throw
  /// away MathLive's own shortcuts (alpha, int, sum, …).
  function configureField(mf, kind) {
    mf.mathVirtualKeyboardPolicy = "manual";
    // A mixed line holds prose and formulas at once. MathLive's own smart mode
    // guesses that in English and garbles German sentences, so it stays off:
    // mixed.js decides instead.
    mf.smartMode = false;
    mf.smartFence = true;
    mf.smartSuperscript = true;
    mf.removeExtraneousParentheses = true;
    mf.menuItems = [];
    const defaults = mf.inlineShortcuts || {};
    mf.inlineShortcuts = { ...defaults, ...EXTRA_SHORTCUTS };
  }

  // ---------------------------------------------------------------- building

  const HINTS = {
    math: "Formel tippen …   /  Bruch   ^ hoch   _ tief   ⌘K Symbole",
    mixed: "Text und Formel – schreib einfach los, x = 1 wird von selbst Formel",
    paragraph: "Text …",
    text: "Notiz …",
    heading: "Überschrift …",
    table: "",
  };

  function buildRow(block) {
    const row = document.createElement("div");
    row.className = `block kind-${block.kind}`;
    row.dataset.id = block.id;
    row.setAttribute("role", "listitem");

    const gutter = document.createElement("div");
    gutter.className = "gutter";
    gutter.textContent = gutterLabel(block);
    row.appendChild(gutter);

    const content = document.createElement("div");
    content.className = "content";
    content.dataset.hint = HINTS[block.kind] || "";
    row.appendChild(content);

    content.appendChild(buildEditor(block));
    updateEmptyState(row, block);
    return row;
  }

  function gutterLabel(block) {
    if (sourceMode.has(block.id)) return "TeX";
    if (block.kind === "paragraph") return "T";
    if (block.kind === "text") return "¶";
    if (block.kind === "heading") return "H";
    if (block.kind === "mixed") return "¶ƒ";
    if (block.kind === "table") return "▦";
    return "ƒ";
  }

  function buildEditor(block) {
    if (block.kind === "math" || block.kind === "mixed") {
      return sourceMode.has(block.id) ? buildSource(block) : buildMath(block);
    }
    if (block.kind === "table") return buildTable(block);
    return buildProse(block);
  }

  /* MathLive treats three of its long arrows as if they took a label: an
     immediately following \left fails to parse outright, and a following \frac
     is silently drawn on top of the arrow instead of after it. An empty group
     ends the command and renders identically, so values are repaired on the way
     into a field — including sheets that already carry the damage. */
  const LONG_ARROW = /(\\long(?:rightarrow|leftarrow|leftrightarrow))(?=\\|\{(?!\}))/g;
  const repairLatex = (latex) => latex.replace(LONG_ARROW, "$1{}");

  function buildMath(block) {
    const mf = document.createElement("math-field");
    mf.value = repairLatex(block.value);
    // `mount` fires once MathLive has upgraded the element and its options are
    // readable; configuring earlier loses the built-in shortcuts.
    mf.addEventListener("mount", () => {
      configureField(mf, block.kind);
      // MathLive lays a field out lazily, so one measurement right after mount
      // can still read zero. A couple of re-checks cost nothing and catch it.
      for (const delay of [0, 150, 600]) {
        setTimeout(() => updateOverflowState(rowOf(block.id)), delay);
      }
    }, { once: true });

    mf.addEventListener("input", () => {
      block.value = window.MixedInput.normalizeLatex(mf.value);
      const row = rowOf(block.id);
      updateEmptyState(row, block);
      updateOverflowState(row);
      scheduleChange();
    });
    mf.addEventListener("focusin", () => setFocused(block.id));
    mf.addEventListener("focusout", () => {
      // "… ist f" and then a click elsewhere: the last word is finished too.
      if (block.kind === "mixed" && indexOf(block.id) >= 0) window.MixedInput.finish(mf);
      updateOverflowState(rowOf(block.id));
    });
    mf.addEventListener("paste", (e) => onPaste(e, block, mf, null), true);
    mf.addEventListener("move-out", (e) => {
      const dir = e.detail.direction;
      const moved =
        dir === "upward" || dir === "backward"
          ? focusSibling(block.id, -1, dir === "backward" ? "end" : "end")
          : focusSibling(block.id, +1, "start");
      if (moved) e.preventDefault();
    });
    mf.addEventListener("keydown", (e) => onMathKeyDown(e, block, mf), true);
    mf.addEventListener("contextmenu", (e) => {
      // The native WebKit menu has nothing useful to say about a formula, and
      // MathLive's own menu is switched off, so Swift puts up its own.
      e.preventDefault();
      e.stopPropagation();
      setFocused(block.id);
      const selected = mf.getValue(mf.selection, "latex");
      Bridge.post("contextmenu", {
        kind: block.kind,
        hasSelection: selected.length > 0,
        isText: /^\\text\{[^{}]*\}$/.test(selected.trim()),
      });
    }, true);
    return mf;
  }

  function buildSource(block) {
    const ta = document.createElement("textarea");
    ta.className = "src";
    ta.spellcheck = false;
    ta.value = block.value;
    const grow = () => {
      ta.style.height = "auto";
      ta.style.height = ta.scrollHeight + "px";
    };
    requestAnimationFrame(grow);
    ta.addEventListener("beforeinput", () => pushHistory(true));
    ta.addEventListener("input", () => {
      block.value = ta.value;
      grow();
      scheduleChange();
    });
    ta.addEventListener("focusin", () => setFocused(block.id));
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        toggleSource(block.id); // back to rendered view
      } else if (e.key === "Escape") {
        e.preventDefault();
        toggleSource(block.id);
      }
    });
    return ta;
  }

  function buildProse(block) {
    const el = document.createElement("div");
    el.className = `prose ${block.kind}`;
    el.contentEditable = "true";
    setProseContent(el, block.value);

    // Paste as plain text: a note should not inherit a web page's fonts and
    // sizes, and the formatting you want is one keystroke away.
    el.addEventListener("paste", (e) => {
      if (onPaste(e, block, el, null)) return;
      e.preventDefault();
      const text = e.clipboardData?.getData("text/plain") ?? "";
      document.execCommand("insertText", false, text);
    });

    el.addEventListener("beforeinput", () => pushHistory(true));
    el.addEventListener("input", () => {
      block.value = sanitizeHTML(el.innerHTML);
      updateEmptyState(rowOf(block.id), block);
      scheduleChange();
    });
    el.addEventListener("focusin", () => setFocused(block.id));
    el.addEventListener("keydown", (e) => onProseKeyDown(e, block, el));
    return el;
  }

  /** Marks a line whose formula is wider than the block, so the fade shows. */
  function updateOverflowState(row) {
    if (!row) return;
    // A table scrolls in its own frame; its first cell says nothing about that.
    if (row.classList.contains("kind-table")) return;
    const field = row.querySelector("math-field");
    const content = field?.shadowRoot?.querySelector(".ML__content");
    if (!content) {
      row.classList.remove("overflows");
      return;
    }
    row.classList.toggle("overflows", content.scrollWidth > content.clientWidth + 2);
  }

  function updateEmptyState(row, block) {
    if (!row) return;
    const empty = isProse(block.kind)
      ? plainText(block.value).trim().length === 0
      : !block.value || block.value.length === 0;
    row.classList.toggle("is-empty", empty);
  }

  const isProse = (kind) =>
    kind === "text" || kind === "paragraph" || kind === "heading";

  // ---------------------------------------------------------------- keys

  /* Keys that only move the caret must not create an undo step. */
  const NAVIGATION_KEYS = new Set([
    "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End",
    "PageUp", "PageDown", "Shift", "Meta", "Control", "Alt", "CapsLock", "Escape",
  ]);

  function onMathKeyDown(e, block, mf) {
    if (!e.metaKey && !e.ctrlKey && !NAVIGATION_KEYS.has(e.key)) pushHistory(true);

    if (block.kind === "mixed") {
      if (e.key === "Enter" || e.key === "Tab") window.MixedInput.finish(mf);
      else if (window.MixedInput.keydown(e, mf)) return;
    } else if (window.MixedInput.scriptBraces(e, mf)) {
      return;
    }

    /* On a German (and Swiss, French, …) layout "^" is a dead key: the browser
       reports key "Dead" and holds the accent for the next character, so
       MathLive never sees a circumflex and "x^2" comes out as literal text or a
       stray â. Catching it here makes the key mean "superscript" every time,
       whatever follows. US layouts are untouched — there Backquote is a plain
       character and never reports "Dead". */
    if (e.key === "Dead" && e.code === "Backquote" && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      e.stopPropagation();
      mf.executeCommand("moveToSuperscript");
      return;
    }
    if (e.metaKey && e.key === "Enter") {
      e.preventDefault();
      insertAfter(block.id, "paragraph");
      return;
    }
    if (e.key === "Enter" && !e.metaKey) {
      e.preventDefault();
      e.stopPropagation();
      if (e.shiftKey) {
        // a new row inside a matrix / cases environment
        mf.executeCommand("addRowAfter");
      } else {
        insertAfter(block.id, block.kind);
      }
      return;
    }
    if (e.key === "Backspace" && mf.value === "" && blocks.length > 1) {
      e.preventDefault();
      e.stopPropagation();
      removeBlock(block.id);
      return;
    }
    if (e.key === "Tab" && !e.shiftKey) {
      // Next placeholder first, otherwise on to the next line. MathLive's own
      // Tab handling is stopped either way, or it would jump a second time.
      e.preventDefault();
      e.stopPropagation();
      if (!movedToNextPlaceholder(mf)) focusSibling(block.id, +1, "start");
    }
  }

  /* Offsets are relative to whichever node the caret sits in, so with formatted
     text "offset 0" can be the middle of the line. Measuring the text before and
     after the caret against the whole line is layout-independent. */
  function caretEdges(el) {
    const selection = window.getSelection();
    if (!selection || !selection.isCollapsed || !el.contains(selection.anchorNode)) {
      return { atStart: false, atEnd: false };
    }
    const before = document.createRange();
    before.selectNodeContents(el);
    before.setEnd(selection.anchorNode, selection.anchorOffset);
    const whole = (el.textContent || "").length;
    const head = before.toString().length;
    return { atStart: head === 0, atEnd: head === whole };
  }

  function onProseKeyDown(e, block, el) {
    const { atStart, atEnd } = caretEdges(el);

    if (e.key === "Enter") {
      e.preventDefault();
      if (e.shiftKey) {
        // A soft break inside the line. Left to the browser this becomes a
        // <div>, which the sanitizer strips — and the break would vanish.
        pushHistory();
        document.execCommand("insertLineBreak");
        block.value = sanitizeHTML(el.innerHTML);
        scheduleChange();
      } else {
        // Same kind again, so writing prose stays prose. Only a heading breaks
        // the pattern: two headings in a row is almost never what was meant.
        insertAfter(block.id, block.kind === "heading" ? "paragraph" : block.kind);
      }
      return;
    }
    if (e.key === "Backspace" && (el.textContent || "").length === 0 && blocks.length > 1) {
      e.preventDefault();
      removeBlock(block.id);
      return;
    }
    if ((e.key === "ArrowUp" || (e.key === "ArrowLeft" && atStart)) && atStart) {
      if (focusSibling(block.id, -1, "end")) e.preventDefault();
      return;
    }
    if ((e.key === "ArrowDown" || (e.key === "ArrowRight" && atEnd)) && atEnd) {
      if (focusSibling(block.id, +1, "start")) e.preventDefault();
    }
  }

  // ---------------------------------------------------------------- focus

  function setFocused(id) {
    if (focusedID === id) return;
    if (activeCell && activeCell.id !== id) activeCell = null;
    document.querySelectorAll(".block.focused").forEach((el) => el.classList.remove("focused"));
    focusedID = id;
    const row = rowOf(id);
    if (row) row.classList.add("focused");
    reportFocus();
  }

  function editorIn(row) {
    if (!row) return null;
    if (row.classList.contains("kind-table")) {
      const id = row.dataset.id;
      const cell = activeCell && activeCell.id === id ? activeCell : { r: 0, c: 0 };
      return cellField(id, cell.r, cell.c) || row.querySelector("math-field");
    }
    return row.querySelector("math-field, textarea.src, .prose");
  }

  function focusBlock(id, where = "end") {
    const block = blocks[indexOf(id)];
    if (block && block.kind === "table") {
      const { rows } = parseTable(block.value);
      return where === "start"
        ? focusCell(id, 0, 0, "start")
        : focusCell(id, rows.length - 1, rows[0].length - 1, "end");
    }
    const row = rowOf(id);
    const el = editorIn(row);
    if (!el || !safeFocus(el)) return false;
    if (el.tagName === "MATH-FIELD") {
      el.position = where === "start" ? 0 : el.lastOffset;
    } else if (el.tagName === "TEXTAREA") {
      const pos = where === "start" ? 0 : el.value.length;
      el.setSelectionRange(pos, pos);
    } else {
      const range = document.createRange();
      range.selectNodeContents(el);
      range.collapse(where === "start");
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    }
    row.scrollIntoView({ block: "nearest" });
    setFocused(id);
    return true;
  }

  /* MathLive remembers the last focused field globally and blurs it when the
     next one takes focus. If that field was removed with its line — undo, a
     table redraw, a new sheet — the blur throws once; the failed attempt clears
     the stale reference, so a second try goes through. */
  function safeFocus(el) {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        el.focus();
        return true;
      } catch (error) {
        if (attempt === 1) Bridge.post("log", { text: `focus: ${error.message}` });
      }
    }
    return false;
  }

  /** Tab jumps to the next placeholder if there is one. `executeCommand`
      reports success either way, so the caret position has to tell. */
  function movedToNextPlaceholder(mf) {
    const before = JSON.stringify(mf.selection);
    mf.executeCommand("moveToNextPlaceholder");
    return JSON.stringify(mf.selection) !== before;
  }

  function focusSibling(id, delta, where) {
    const next = indexOf(id) + delta;
    if (next < 0 || next >= blocks.length) return false;
    return focusBlock(blocks[next].id, where);
  }

  // ---------------------------------------------------------------- formatting

  /* Bold and italic have to be asked for twice in a formula: `variantStyle`
     covers the maths runs and `fontSeries`/`fontShape` the \text{…} runs, and a
     mixed line usually contains both. Underline is not a MathLive style at all,
     so it is done by wrapping the selection in \underline{}. */
  const MATH_BOLD = { variantStyle: "bold", fontSeries: "b" };
  const MATH_ITALIC = { variantStyle: "italic", fontShape: "it" };

  /* Highlighting also pins the ink to a dark tone. A marker colour is light by
     nature, and in dark mode the inherited light text would otherwise sit on a
     light background and disappear. */
  const HIGHLIGHT_INK = "#1a1a1a";

  const focusedEditor = () => editorIn(rowOf(focusedID));
  const isMath = (el) => el && el.tagName === "MATH-FIELD";

  /** With nothing selected, formatting applies to the whole line. */
  function ensureSelection(el) {
    if (isMath(el)) {
      if (!el.getValue(el.selection, "latex")) el.executeCommand("selectAll");
      return;
    }
    const selection = window.getSelection();
    if (!selection) return;
    if (selection.isCollapsed || !el.contains(selection.anchorNode)) {
      const range = document.createRange();
      range.selectNodeContents(el);
      selection.removeAllRanges();
      selection.addRange(range);
    }
  }

  function commit(el) {
    const block = blocks[indexOf(focusedID)];
    if (!block) return;
    if (block.kind === "table") {
      updateCell(block, Number(el.dataset.r), Number(el.dataset.c), window.MixedInput.normalizeLatex(el.value));
      return;
    }
    block.value = isMath(el) ? window.MixedInput.normalizeLatex(el.value) : sanitizeHTML(el.innerHTML);
    updateEmptyState(rowOf(block.id), block);
    scheduleChange();
  }

  /** Prepares the focused editor, or `null` if this one cannot be formatted
      (the raw LaTeX view is plain text on purpose). */
  function editorForFormatting() {
    const el = focusedEditor();
    if (!el || el.tagName === "TEXTAREA") return null;
    el.focus();
    ensureSelection(el);
    return el;
  }

  function toggleUnderline(mf) {
    const selected = mf.getValue(mf.selection, "latex");
    const wrapped = /^\\underline\{([\s\S]*)\}$/.exec(selected.trim());
    mf.insert(wrapped ? wrapped[1] : `\\underline{${selected}}`,
              { format: "latex", mode: "math", selectionMode: "item" });
  }

  /* mixed.js decides while you type whether something is a word or a formula,
     and it is right most of the time — but not always. These turn a selection
     into the other kind after the fact, which is what the right-click menu offers.

     "plain-text" is what MathLive reads the selection as, so a run of letters it
     mistook for a product of variables comes back as the word you meant. */
  function convertSelection(to) {
    pushHistory();
    const el = focusedEditor();
    if (!isMath(el)) return false;
    const selected = el.getValue(el.selection, "latex");
    if (!selected) return false;

    if (to === "text") {
      const words = el.getValue(el.selection, "plain-text");
      el.insert(`\\text{${words}}`, { format: "latex", mode: "math", selectionMode: "item" });
    } else {
      // Unwrap every \text{…} run; what is left is read as maths again.
      const bare = selected.replace(/\\text\{([^{}]*)\}/g, "$1");
      el.insert(bare, { format: "latex", mode: "math", selectionMode: "item" });
    }
    commit(el);
    return true;
  }

  function applyFormat(what) {
    pushHistory();
    const el = editorForFormatting();
    if (!el) return false;
    if (isMath(el)) {
      if (what === "bold") el.applyStyle(MATH_BOLD, { operation: "toggle" });
      else if (what === "italic") el.applyStyle(MATH_ITALIC, { operation: "toggle" });
      else if (what === "underline") toggleUnderline(el);
      else return false;
    } else {
      document.execCommand("styleWithCSS", false, true);
      document.execCommand(what, false, null);
    }
    commit(el);
    return true;
  }

  function applyColor(hex) {
    pushHistory();
    const el = editorForFormatting();
    if (!el) return false;
    const clearing = !hex || hex === "none";
    if (isMath(el)) {
      el.applyStyle({ color: clearing ? "none" : hex }, { operation: "set" });
    } else {
      document.execCommand("styleWithCSS", false, true);
      document.execCommand("foreColor", false, clearing ? "inherit" : hex);
    }
    commit(el);
    return true;
  }

  function applyHighlight(hex) {
    pushHistory();
    const el = editorForFormatting();
    if (!el) return false;
    const clearing = !hex || hex === "none";
    if (isMath(el)) {
      el.applyStyle({ backgroundColor: clearing ? "none" : hex,
                      color: clearing ? "none" : HIGHLIGHT_INK },
                    { operation: "set" });
    } else {
      document.execCommand("styleWithCSS", false, true);
      document.execCommand("hiliteColor", false, clearing ? "transparent" : hex);
      document.execCommand("foreColor", false, clearing ? "inherit" : HIGHLIGHT_INK);
    }
    commit(el);
    return true;
  }

  function clearFormatting() {
    pushHistory();
    const el = editorForFormatting();
    if (!el) return false;
    if (isMath(el)) {
      el.applyStyle({ variantStyle: "auto", fontSeries: "auto", fontShape: "auto",
                      color: "none", backgroundColor: "none" },
                    { operation: "set" });
      const selected = el.getValue(el.selection, "latex");
      const wrapped = /^\\underline\{([\s\S]*)\}$/.exec(selected.trim());
      if (wrapped) el.insert(wrapped[1], { format: "latex", mode: "math", selectionMode: "item" });
    } else {
      document.execCommand("removeFormat");
    }
    commit(el);
    return true;
  }

  // ---------------------------------------------------------------- structure

  function insertAfter(id, kind, value = "") {
    pushHistory();
    const block = { id: uid(), kind, value };
    const at = id == null ? blocks.length : indexOf(id) + 1;
    blocks.splice(at, 0, block);
    const row = buildRow(block);
    const anchor = id == null ? null : rowOf(id);
    if (anchor && anchor.nextSibling) sheetEl().insertBefore(row, anchor.nextSibling);
    else if (anchor) sheetEl().appendChild(row);
    else sheetEl().appendChild(row);
    focusBlock(block.id, "start");
    scheduleChange();
    return block.id;
  }

  function removeBlock(id) {
    const i = indexOf(id);
    if (i < 0 || blocks.length <= 1) return;
    pushHistory();
    const target = blocks[i - 1] || blocks[i + 1];
    blocks.splice(i, 1);
    sourceMode.delete(id);
    rowOf(id)?.remove();
    if (target) focusBlock(target.id, "end");
    scheduleChange();
  }

  /** Replace a block's editor in place, keeping its value. */
  function rebuild(id, where = "end") {
    const block = blocks[indexOf(id)];
    const row = rowOf(id);
    if (!block || !row) return;
    row.className = `block kind-${block.kind}`;
    row.querySelector(".gutter").textContent = gutterLabel(block);
    const content = row.querySelector(".content");
    content.dataset.hint = HINTS[block.kind] || "";
    content.replaceChildren(buildEditor(block));
    updateEmptyState(row, block);
    focusBlock(id, where);
  }

  function setKind(id, kind) {
    const block = blocks[indexOf(id)];
    // A grid of cells has no one-line reading to switch to and back from.
    if (!block || block.kind === kind || block.kind === "table" || kind === "table") return;
    pushHistory();

    if (isProse(block.kind) !== isProse(kind)) {
      const next = convertedValue(block, kind);
      block.alt = { kind: block.kind, value: block.value };
      block.value = next;
    }
    block.kind = kind;
    sourceMode.delete(id);
    rebuild(id);
    scheduleChange();
    reportFocus();
  }

  function toggleSource(id) {
    const block = blocks[indexOf(id)];
    if (!block || (block.kind !== "math" && block.kind !== "mixed")) return;
    if (sourceMode.has(id)) sourceMode.delete(id);
    else sourceMode.add(id);
    rebuild(id);
    reportFocus();
  }

  function moveBlock(id, delta) {
    const i = indexOf(id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= blocks.length) return;
    pushHistory();
    const [block] = blocks.splice(i, 1);
    blocks.splice(j, 0, block);
    const row = rowOf(id);
    const other = rowOf(blocks[delta > 0 ? j - 1 : j + 1].id);
    if (delta > 0) other.after(row);
    else other.before(row);
    focusBlock(id, "end");
    scheduleChange();
  }

  /** The body of `MP.insertBlocks`, kept out of the history-suspending wrapper. */
  function insertBlocksInner(list) {
    let anchor = focusedID;
    let first = 0;

    // An empty line at the caret is reused rather than left hanging above
    // the import.
    const current = blocks[indexOf(anchor)];
    if (current && current.value === "") {
      current.kind = list[0].kind || "math";
      current.value = list[0].value || "";
      sourceMode.delete(current.id);
      rebuild(current.id);
      first = 1;
    }

    for (let i = first; i < list.length; i += 1) {
      anchor = insertAfter(anchor, list[i].kind || "math", list[i].value || "");
    }
    scheduleChange();
    return list.length;
  }

  // ---------------------------------------------------------------- pasting

  /* What arrives from outside — a ChatGPT answer, a lecture page, Markdown — is
     parsed by paste.js into text and formulas and lands as the right kind of
     line: a sentence with formulas as "Text + Formel", a displayed equation as
     "Formel", a heading as a heading. The whole paste is one undo step. */

  const isEmptyValue = (block) => (isProse(block.kind)
    ? plainText(block.value).trim() === ""
    : block.value === "");

  /** Plain sentences in a mixed target get the same reading typing gives them. */
  function classifyParagraphs(paragraphs) {
    return paragraphs.map((p) => {
      if (p.type !== "line" || p.heading) return p;
      const runs = p.runs.flatMap((run) => (run.t === "text" && !run.bold && !run.italic
        ? window.MixedInput.classifyPlain(run.text)
        : [run]));
      return { ...p, runs: window.MathPaste.tidyRuns(runs) };
    });
  }

  /**
   * Handles a paste into `field` of `block` (`cell` for a table cell). Returns
   * `true` if it took over; `false` leaves the paste to the field.
   */
  function onPaste(e, block, field, cell) {
    const data = e.clipboardData;
    if (!data || !window.MathPaste) return false;
    const types = [...(data.types || [])];
    // Copied from a formula field: MathLive's own format is already exact.
    if (types.includes("application/x-latex")) return false;

    const html = data.getData("text/html") || "";
    const plain = data.getData("text/plain") || "";
    let paragraphs = window.MathPaste.parseClipboard(html, plain);
    if (!paragraphs.length) return false;
    let math = window.MathPaste.hasMath(paragraphs);

    const prose = isProse(block.kind);
    const mixedTarget = block.kind === "mixed" || cell;
    // A formula line reads pasted plain text as maths itself (AsciiMath);
    // a text line takes plain text as text.
    if (!math && paragraphs.length === 1 && !mixedTarget) return false;
    if (!math && mixedTarget) {
      paragraphs = classifyParagraphs(paragraphs);
      math = window.MathPaste.hasMath(paragraphs);
    }

    e.preventDefault();
    e.stopPropagation();
    // The field's own paste handling and a DOM rebuild must not overlap, so the
    // sheet changes right after the event instead of inside it.
    setTimeout(() => {
      pushHistory();
      historySuspended = true;
      try {
        applyPaste(block, field, cell, paragraphs, prose);
      } catch (error) {
        Bridge.post("log", { text: `paste: ${error.message}` });
      } finally {
        historySuspended = false;
      }
    }, 0);
    return true;
  }

  function applyPaste(block, field, cell, paragraphs, prose) {
    if (indexOf(block.id) < 0) return;

    if (cell) {
      // A cell is one line: paragraphs are joined, tables flattened.
      const latex = paragraphs.map((p) => {
        if (p.type === "display") return p.latex;
        if (p.type === "line") return window.MathPaste.runsToLatex(p.runs);
        return p.rows.map((row) => row.map(window.MathPaste.runsToLatex).join("\\text{ }")).join("\\text{ }");
      }).filter(Boolean).join("\\text{ }");
      safeFocus(field);
      field.insert(latex, { format: "latex", mode: "math", insertionMode: "replaceSelection", selectionMode: "after" });
      commit(field);
      return;
    }

    const list = window.MathPaste.toBlocks(paragraphs);
    if (!list.length) return;
    // Prose pasted into a mixed line keeps the line mixed; it is still the line
    // you chose to write formulas in.
    if (block.kind === "mixed" && list[0].kind === "paragraph" && paragraphs[0].type === "line") {
      list[0] = { kind: "mixed", value: window.MathPaste.runsToLatex(paragraphs[0].runs) };
    }
    let anchor = block.id;
    let first = 0;

    if (isEmptyValue(block)) {
      // An empty line simply becomes the first pasted line.
      block.kind = list[0].kind;
      block.value = list[0].value;
      delete block.alt;
      sourceMode.delete(block.id);
      rebuild(block.id, "end");
      first = 1;
    } else if (!prose && (list[0].kind === "mixed" || list[0].kind === "math") && field.tagName === "MATH-FIELD") {
      // Into the formula at the caret. A mixed piece in a pure formula line
      // turns the line into a mixed one, so its words stay words.
      safeFocus(field);
      field.insert(list[0].value, { format: "latex", mode: "math", insertionMode: "replaceSelection", selectionMode: "after" });
      commit(field);
      if (list[0].kind === "mixed" && block.kind === "math") {
        block.kind = "mixed";
        rebuild(block.id, "end");
      }
      first = 1;
    } else if (prose && (list[0].kind === "paragraph" || list[0].kind === "heading")) {
      safeFocus(field);
      document.execCommand("insertHTML", false, sanitizeHTML(list[0].value));
      block.value = sanitizeHTML(field.innerHTML);
      first = 1;
    }

    for (let i = first; i < list.length; i += 1) {
      anchor = insertAfter(anchor, list[i].kind, list[i].value);
    }
    scheduleChange();
    reportFocus();
  }

  // ---------------------------------------------------------------- tables

  /* A table is one line of the sheet whose value is JSON: a grid of cells, each
     holding the same LaTeX a "Text + Formel" line holds, so a cell can say
     "Nullstelle" as easily as "x^2-1". Every edit parses the stored value and
     writes it back, so the DOM never keeps a second copy that could drift from
     what undo and saving see. */

  const ALIGNMENTS = ["left", "center", "right"];
  const LINE_STYLES = ["grid", "lines", "none"];

  function parseTable(value) {
    let data = null;
    try { data = JSON.parse(value); } catch (_) { /* treated as a fresh table */ }
    const raw = Array.isArray(data?.rows) && data.rows.some(Array.isArray)
      ? data.rows.filter(Array.isArray)
      : [["", ""], ["", ""]];
    const cols = Math.max(1, ...raw.map((row) => row.length));
    const column = (list, pick) => Array.from({ length: cols }, (_, c) => pick(list?.[c]));
    return {
      rows: raw.map((row) => column(row, (cell) => (typeof cell === "string" ? cell : ""))),
      header: data?.header === true,
      style: LINE_STYLES.includes(data?.style) ? data.style : "grid",
      align: column(data?.align, (a) => (ALIGNMENTS.includes(a) ? a : "left")),
      widths: column(data?.widths, (w) => (typeof w === "number" && w > 0 ? w : null)),
    };
  }

  /** Keys in a fixed order, so an unchanged table serialises to the same string. */
  const serializeTable = (t) =>
    JSON.stringify({ rows: t.rows, header: t.header, style: t.style, align: t.align, widths: t.widths });

  function emptyTable(rows, cols) {
    return {
      rows: Array.from({ length: rows }, () => Array(cols).fill("")),
      header: true,
      style: "grid",
      align: Array(cols).fill("left"),
      widths: Array(cols).fill(null),
    };
  }

  const cellField = (id, r, c) =>
    rowOf(id)?.querySelector(`math-field[data-r="${r}"][data-c="${c}"]`) || null;

  function tableFocus(block) {
    const t = parseTable(block.value);
    const cell = activeCell && activeCell.id === block.id ? activeCell : { r: 0, c: 0 };
    return {
      row: cell.r,
      column: cell.c,
      rows: t.rows.length,
      columns: t.rows[0].length,
      header: t.header,
      style: t.style,
      align: t.align[cell.c] || "left",
    };
  }

  function updateCell(block, r, c, latex) {
    const t = parseTable(block.value);
    if (!t.rows[r] || c >= t.rows[r].length) return;
    t.rows[r][c] = latex;
    block.value = serializeTable(t);
    scheduleChange();
  }

  function buildTable(block) {
    const t = parseTable(block.value);
    const cols = t.rows[0].length;

    const wrap = document.createElement("div");
    wrap.className = "table-wrap";

    const scroller = document.createElement("div");
    scroller.className = "table-scroll";
    wrap.appendChild(scroller);

    const table = document.createElement("table");
    table.className = `mp-table lines-${t.style}${t.header ? " has-header" : ""}`;
    scroller.appendChild(table);

    const colgroup = document.createElement("colgroup");
    for (let c = 0; c < cols; c += 1) {
      const col = document.createElement("col");
      if (t.widths[c]) col.style.width = `${t.widths[c]}em`;
      colgroup.appendChild(col);
    }
    table.appendChild(colgroup);

    const body = document.createElement("tbody");
    t.rows.forEach((cells, r) => {
      const tr = document.createElement("tr");
      cells.forEach((latex, c) => {
        const td = document.createElement("td");
        td.className = `align-${t.align[c]}`;
        td.appendChild(buildCell(block, latex, r, c));
        const grip = document.createElement("div");
        grip.className = "col-grip";
        grip.title = "Ziehen: Spaltenbreite · Doppelklick: automatisch";
        grip.addEventListener("mousedown", (e) => startColumnResize(e, block, c, table));
        grip.addEventListener("dblclick", (e) => {
          e.preventDefault();
          editTable(block.id, (tt) => { tt.widths[c] = null; }, { r, c });
        });
        td.appendChild(grip);
        // A click on the cell's padding still lands in the formula.
        td.addEventListener("mousedown", (e) => {
          if (e.target !== td) return;
          e.preventDefault();
          focusCell(block.id, r, c, "end");
        });
        tr.appendChild(td);
      });
      body.appendChild(tr);
    });
    table.appendChild(body);

    const addColumn = document.createElement("button");
    addColumn.className = "table-add add-column";
    addColumn.textContent = "+";
    addColumn.title = "Spalte anfügen";
    const addRow = document.createElement("button");
    addRow.className = "table-add add-row";
    addRow.textContent = "+";
    addRow.title = "Zeile anfügen";
    for (const button of [addColumn, addRow]) {
      // Keep the caret where it is until the new cell takes it.
      button.addEventListener("mousedown", (e) => e.preventDefault());
    }
    addColumn.addEventListener("click", () => {
      const r = activeCell && activeCell.id === block.id ? activeCell.r : 0;
      tableCommand(block.id, "columnEnd", null, { r, c: cols - 1 });
    });
    addRow.addEventListener("click", () => {
      const c = activeCell && activeCell.id === block.id ? activeCell.c : 0;
      tableCommand(block.id, "rowEnd", null, { r: t.rows.length - 1, c });
    });
    scroller.appendChild(addColumn);
    wrap.appendChild(addRow);
    return wrap;
  }

  function buildCell(block, latex, r, c) {
    const mf = document.createElement("math-field");
    mf.dataset.r = r;
    mf.dataset.c = c;
    mf.value = repairLatex(latex);
    mf.addEventListener("mount", () => configureField(mf, "mixed"), { once: true });

    mf.addEventListener("input", () => updateCell(block, r, c, window.MixedInput.normalizeLatex(mf.value)));
    mf.addEventListener("focusout", () => {
      if (indexOf(block.id) >= 0) window.MixedInput.finish(mf);
    });
    mf.addEventListener("paste", (e) => onPaste(e, block, mf, { r, c }), true);
    mf.addEventListener("focusin", () => setActiveCell(block.id, r, c));
    mf.addEventListener("move-out", (e) => {
      if (moveOutOfCell(block, r, c, e.detail.direction)) e.preventDefault();
    });
    mf.addEventListener("keydown", (e) => onCellKeyDown(e, block, mf, r, c), true);
    mf.addEventListener("contextmenu", (e) => {
      e.preventDefault();
      e.stopPropagation();
      setActiveCell(block.id, r, c);
      const selected = mf.getValue(mf.selection, "latex");
      Bridge.post("contextmenu", {
        kind: "table",
        hasSelection: selected.length > 0,
        isText: /^\\text\{[^{}]*\}$/.test(selected.trim()),
        table: tableFocus(block),
      });
    }, true);
    return mf;
  }

  function setActiveCell(id, r, c) {
    const changed = !activeCell || activeCell.id !== id || activeCell.r !== r || activeCell.c !== c;
    const row = rowOf(id);
    row?.querySelectorAll("td.active").forEach((td) => td.classList.remove("active"));
    cellField(id, r, c)?.parentElement?.classList.add("active");
    if (focusedID !== id) {
      setFocused(id); // reports focus itself, with the cell already set below
    }
    activeCell = { id, r, c };
    if (changed) reportFocus();
  }

  function focusCell(id, r, c, where = "end") {
    const block = blocks[indexOf(id)];
    if (!block) return false;
    const t = parseTable(block.value);
    r = Math.max(0, Math.min(r, t.rows.length - 1));
    c = Math.max(0, Math.min(c, t.rows[0].length - 1));
    const field = cellField(id, r, c);
    if (!field || !safeFocus(field)) return false;
    field.position = where === "start" ? 0 : field.lastOffset;
    setActiveCell(id, r, c);
    field.parentElement.scrollIntoView({ block: "nearest", inline: "nearest" });
    return true;
  }

  function moveOutOfCell(block, r, c, direction) {
    const t = parseTable(block.value);
    const rows = t.rows.length;
    const cols = t.rows[0].length;
    switch (direction) {
      case "forward":
        if (c + 1 < cols) return focusCell(block.id, r, c + 1, "start");
        if (r + 1 < rows) return focusCell(block.id, r + 1, 0, "start");
        return focusSibling(block.id, +1, "start");
      case "backward":
        if (c > 0) return focusCell(block.id, r, c - 1, "end");
        if (r > 0) return focusCell(block.id, r - 1, cols - 1, "end");
        return focusSibling(block.id, -1, "end");
      case "upward":
        if (r > 0) return focusCell(block.id, r - 1, c, "end");
        return focusSibling(block.id, -1, "end");
      case "downward":
        if (r + 1 < rows) return focusCell(block.id, r + 1, c, "start");
        return focusSibling(block.id, +1, "start");
      default:
        return false;
    }
  }

  function onCellKeyDown(e, block, mf, r, c) {
    const t = parseTable(block.value);
    const rows = t.rows.length;
    const cols = t.rows[0].length;
    const plain = !e.metaKey && !e.ctrlKey && !e.altKey;

    if (!e.metaKey && !e.ctrlKey && !NAVIGATION_KEYS.has(e.key)
        && e.key !== "Tab" && e.key !== "Enter") {
      pushHistory(true);
    }

    if (e.key === "Enter" || e.key === "Tab") window.MixedInput.finish(mf);
    else if (window.MixedInput.keydown(e, mf)) return;

    const stop = () => { e.preventDefault(); e.stopPropagation(); };

    if (e.key === "Dead" && e.code === "Backquote" && plain) {
      stop();
      mf.executeCommand("moveToSuperscript");
      return;
    }
    if (e.key === "Enter" && e.metaKey) {
      stop();
      insertAfter(block.id, "paragraph");
      return;
    }
    if (e.key === "Enter" && e.shiftKey) {
      stop();
      mf.executeCommand("addRowAfter"); // inside a matrix in the cell
      return;
    }
    if (e.key === "Enter" && plain) {
      // Down the column, like a spreadsheet; past the last row a new one appears.
      stop();
      if (r + 1 < rows) focusCell(block.id, r + 1, c, "end");
      else tableCommand(block.id, "rowBelow", null, { r, c });
      return;
    }
    if (e.key === "Tab" && !e.shiftKey && plain) {
      stop();
      if (movedToNextPlaceholder(mf)) return;
      if (c + 1 < cols) focusCell(block.id, r, c + 1, "end");
      else if (r + 1 < rows) focusCell(block.id, r + 1, 0, "end");
      // Tab in the last cell grows the table, as in every word processor.
      else tableCommand(block.id, "rowBelow", null, { r, c: 0 });
      return;
    }
    if (e.key === "Tab" && e.shiftKey && plain) {
      stop();
      if (c > 0) focusCell(block.id, r, c - 1, "end");
      else if (r > 0) focusCell(block.id, r - 1, cols - 1, "end");
      else focusSibling(block.id, -1, "end");
      return;
    }
    if (e.key === "Backspace" && mf.value === "" && blocks.length > 1
        && t.rows.every((row) => row.every((cell) => cell === ""))) {
      // Only a table with nothing left in it goes on backspace — never one
      // whose content would be lost with a stray keypress.
      stop();
      removeBlock(block.id);
    }
  }

  /** Mutates the table behind `id`, redraws it and puts the caret in `focus`. */
  function editTable(id, change, focus) {
    const block = blocks[indexOf(id)];
    if (!block || block.kind !== "table") return false;
    const t = parseTable(block.value);
    const before = serializeTable(t);
    const result = change(t);
    if (result === "remove") {
      removeBlock(id);
      return true;
    }
    const after = serializeTable(t);
    if (after === before) return false;

    pushHistory();
    block.value = after;
    const row = rowOf(id);
    if (row) {
      blurFields(row);
      row.querySelector(".content").replaceChildren(buildTable(block));
      const cell = focus || { r: 0, c: 0 };
      focusCell(id, Math.min(cell.r, t.rows.length - 1), Math.min(cell.c, t.rows[0].length - 1), "end");
    }
    scheduleChange();
    reportFocus();
    return true;
  }

  /** Every structural table operation, by name — the menus in Swift use these. */
  function tableCommand(id, action, arg, at) {
    const cell = at || (activeCell && activeCell.id === id ? activeCell : { r: 0, c: 0 });
    const { r, c } = cell;
    const insertColumn = (t, index) => {
      t.rows.forEach((row) => row.splice(index, 0, ""));
      t.align.splice(index, 0, t.align[Math.min(index, t.align.length - 1)] || "left");
      t.widths.splice(index, 0, null);
    };

    switch (action) {
      case "rowAbove":
        return editTable(id, (t) => { t.rows.splice(r, 0, Array(t.rows[0].length).fill("")); }, { r, c });
      case "rowBelow":
        return editTable(id, (t) => { t.rows.splice(r + 1, 0, Array(t.rows[0].length).fill("")); }, { r: r + 1, c });
      case "rowEnd":
        return editTable(id, (t) => { t.rows.push(Array(t.rows[0].length).fill("")); }, { r: r + 1, c });
      case "columnLeft":
        return editTable(id, (t) => insertColumn(t, c), { r, c });
      case "columnRight":
        return editTable(id, (t) => insertColumn(t, c + 1), { r, c: c + 1 });
      case "columnEnd":
        return editTable(id, (t) => insertColumn(t, t.rows[0].length), { r, c: c + 1 });
      case "deleteRow":
        return editTable(id, (t) => {
          if (t.rows.length <= 1) return "remove";
          t.rows.splice(r, 1);
        }, { r, c }); // clamped to the new last row if that was the one removed
      case "deleteColumn":
        return editTable(id, (t) => {
          if (t.rows[0].length <= 1) return "remove";
          t.rows.forEach((row) => row.splice(c, 1));
          t.align.splice(c, 1);
          t.widths.splice(c, 1);
        }, { r, c });
      case "toggleHeader":
        return editTable(id, (t) => { t.header = !t.header; }, { r, c });
      case "align":
        if (!ALIGNMENTS.includes(arg)) return false;
        return editTable(id, (t) => { t.align[c] = arg; }, { r, c });
      case "lines":
        if (!LINE_STYLES.includes(arg)) return false;
        return editTable(id, (t) => { t.style = arg; }, { r, c });
      case "resetWidths":
        return editTable(id, (t) => { t.widths = t.widths.map(() => null); }, { r, c });
      case "deleteTable":
        return editTable(id, () => "remove");
      default:
        return false;
    }
  }

  /* Column widths are dragged in pixels but stored in em, so a table keeps its
     proportions when the sheet is zoomed with ⌘+ and ⌘−. */
  function startColumnResize(e, block, c, table) {
    e.preventDefault();
    e.stopPropagation();
    const col = table.querySelectorAll("col")[c];
    const cell = table.rows[0]?.cells[c];
    if (!col || !cell) return;
    const startX = e.clientX;
    const startWidth = cell.getBoundingClientRect().width;
    const em = parseFloat(getComputedStyle(table).fontSize) || 21;
    let width = startWidth;
    table.classList.add("resizing");

    const move = (ev) => {
      width = Math.max(em * 1.5, startWidth + ev.clientX - startX);
      col.style.width = `${width}px`;
    };
    const up = () => {
      document.removeEventListener("mousemove", move);
      document.removeEventListener("mouseup", up);
      table.classList.remove("resizing");
      if (Math.abs(width - startWidth) < 1) return;
      const r = activeCell && activeCell.id === block.id ? activeCell.r : 0;
      editTable(block.id, (t) => { t.widths[c] = Math.round((width / em) * 100) / 100; }, { r, c });
    };
    document.addEventListener("mousemove", move);
    document.addEventListener("mouseup", up);
  }

  /** A fresh table replaces an empty line at the caret, or goes in below it. */
  function insertTable(rows, cols) {
    rows = Math.max(1, Math.min(Number(rows) || 3, 50));
    cols = Math.max(1, Math.min(Number(cols) || 3, 20));
    const value = serializeTable(emptyTable(rows, cols));
    const current = blocks[indexOf(focusedID)];
    const blank = current && current.kind !== "table" && (isProse(current.kind)
      ? plainText(current.value).trim() === ""
      : current.value === "");

    if (blank) {
      pushHistory();
      current.kind = "table";
      current.value = value;
      delete current.alt;
      sourceMode.delete(current.id);
      rebuild(current.id, "start");
      scheduleChange();
      reportFocus();
      return current.id;
    }
    return insertAfter(focusedID, "table", value);
  }

  // ---------------------------------------------------------------- Swift API

  window.MP = {
    setDocument(payload) {
      loading = true;
      blocks = (payload.blocks || []).map((b) => ({
        id: b.id,
        kind: b.kind || "math",
        value: b.value || "",
      }));
      if (blocks.length === 0) blocks.push({ id: uid(), kind: "math", value: "" });
      renderAll(blocks[0].id);
      // A different sheet starts with an empty history — undo must never reach
      // across from one sheet into another.
      history.past.length = 0;
      history.future.length = 0;
      loading = false;
    },

    undo() {
      return undo();
    },
    redo() {
      return redo();
    },

    setTheme(theme) {
      document.documentElement.dataset.theme = theme;
    },

    setFontSize(px) {
      document.documentElement.style.setProperty("--size", px + "px");
    },

    /** Insert LaTeX at the caret of the focused math block. */
    insertLatex(latex) {
      const row = rowOf(focusedID);
      const el = editorIn(row);
      if (!el) return false;
      if (el.tagName === "MATH-FIELD") {
        el.focus();
        pushHistory();
        el.insert(latex, { focus: true, format: "latex", mode: "math", selectionMode: "placeholder" });
        commit(el);
        return true;
      }
      if (el.tagName === "TEXTAREA") {
        const start = el.selectionStart;
        el.setRangeText(latex, start, el.selectionEnd, "end");
        el.dispatchEvent(new Event("input"));
        el.focus();
        return true;
      }
      // focused on prose: open a fresh math block instead of refusing
      const id = insertAfter(focusedID, "math");
      return window.MP.insertLatex(latex) || Boolean(id);
    },

    /** Bold, italic or underline — works in formulas and in notes alike. */
    format(what) {
      return applyFormat(what);
    },
    /** Ink colour; `null` or "none" goes back to the theme colour. */
    setColor(hex) {
      return applyColor(hex);
    },
    /** Highlighter; `null` or "none" removes it. */
    setHighlight(hex) {
      return applyHighlight(hex);
    },
    clearFormatting() {
      return clearFormatting();
    },
    /** Turn the selection into prose or back into maths. */
    convertSelection(to) {
      return convertSelection(to);
    },

    newBlock(kind) {
      insertAfter(focusedID, kind || "math");
    },

    /** A new rows × cols table at the caret. */
    newTable(rows, cols) {
      return insertTable(rows, cols);
    },
    /** A structural change to the table the caret is in (see `tableCommand`). */
    table(action, arg) {
      const block = blocks[indexOf(focusedID)];
      if (!block || block.kind !== "table") return false;
      return tableCommand(block.id, action, arg);
    },

    /** Drop a batch of recognised lines in after the caret. */
    insertBlocks(payload) {
      const list = payload.blocks || [];
      if (!list.length) return 0;

      // A whole worksheet arriving is one step back, not thirty.
      pushHistory();
      historySuspended = true;
      try {
        return insertBlocksInner(list);
      } finally {
        historySuspended = false;
      }
    },
    setKind(kind) {
      if (focusedID) setKind(focusedID, kind);
    },
    toggleSource() {
      if (focusedID) toggleSource(focusedID);
    },
    deleteBlock() {
      if (focusedID) removeBlock(focusedID);
    },
    moveUp() {
      if (focusedID) moveBlock(focusedID, -1);
    },
    moveDown() {
      if (focusedID) moveBlock(focusedID, +1);
    },
    duplicateBlock() {
      const block = blocks[indexOf(focusedID)];
      if (block) insertAfter(block.id, block.kind, block.value);
    },
    refocus() {
      if (focusedID) focusBlock(focusedID, "end");
      else if (blocks.length) focusBlock(blocks[0].id, "end");
    },

    /** The sheet as it is right now — the store may be a debounce behind. */
    snapshotBlocks() {
      return JSON.stringify(blocks.map(({ id, kind, value }) => ({ id, kind, value })));
    },

    /** Lays `payload.blocks` out for paper (see print.js). Used by the PDF
        export in its own, invisible web view — never in the editor itself. */
    preparePrint(payload) {
      document.getElementById("sheet").style.display = "none";
      document.getElementById("tail").style.display = "none";
      return window.MathPrint.build(payload.blocks || [], { width: payload.width, sanitize: sanitizeHTML, repairLatex });
    },

    /** Hide the editing chrome so an exported PDF looks like a clean page. */
    setExportMode(on) {
      document.getElementById("tail").style.display = on ? "none" : "";
      document.documentElement.classList.toggle("exporting", Boolean(on));
      if (on) {
        document.querySelectorAll(".block.focused").forEach((el) => el.classList.remove("focused"));
      } else if (focusedID) {
        rowOf(focusedID)?.classList.add("focused");
      }
    },

    /** LaTeX of the focused block (or of its selection, if there is one). */
    focusedLatex() {
      const el = editorIn(rowOf(focusedID));
      if (!el) return "";
      if (el.tagName === "MATH-FIELD") {
        const sel = el.getValue(el.selection, "latex");
        return sel && sel.length ? sel : el.value;
      }
      if (el.tagName === "TEXTAREA") return el.value;
      return el.textContent || "";
    },

    /** MathML of the focused block — for pasting into Word / Pages. */
    focusedMathML() {
      const el = editorIn(rowOf(focusedID));
      if (el && el.tagName === "MATH-FIELD") return el.getValue("math-ml");
      return "";
    },

    /** Plain-text (ASCIIMath-ish) rendering of the focused block. */
    focusedASCII() {
      const el = editorIn(rowOf(focusedID));
      if (el && el.tagName === "MATH-FIELD") return el.getValue("ascii-math");
      return "";
    },
  };

  // ---------------------------------------------------------------- wiring

  document.getElementById("tail").addEventListener("mousedown", (e) => {
    e.preventDefault();
    const last = blocks[blocks.length - 1];
    if (last && last.value === "") focusBlock(last.id, "end");
    else insertAfter(null, "math");
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") Bridge.post("escape", {});
  });

  /* Caught in the capture phase so MathLive's own, field-local undo never runs:
     one stack for the whole sheet is easier to predict than two that disagree. */
  document.addEventListener("keydown", (e) => {
    if (!(e.metaKey || e.ctrlKey) || e.key.toLowerCase() !== "z") return;
    e.preventDefault();
    e.stopPropagation();
    if (e.shiftKey) redo();
    else undo();
  }, true);

  // A narrower window turns short lines into long ones.
  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      document.querySelectorAll(".block").forEach(updateOverflowState);
    }, 120);
  });

  // Start with an empty sheet until Swift sends the real document.
  window.MP.setDocument({ blocks: [] });
  ready.then(() => Bridge.post("ready", {}));
})();
