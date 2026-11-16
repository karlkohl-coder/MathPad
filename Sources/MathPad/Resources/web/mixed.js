/* MathPad — typing in a "Text + Formel" line.
 *
 * MathLive's own smart mode guesses per keystroke and guesses in English: only
 * "a" and "I" count as words, anything under three letters stays maths, and its
 * shortcuts fire in the middle of words — "Beispiel" became "Beis π el",
 * "gilt" became "gi<", and after "x_1" the rest of the sentence ended up in the
 * subscript.
 *
 * The rules here are few and predictable instead:
 *
 *   You write text. A word becomes a formula when it is finished and plainly is
 *   one: a single letter (x, f, A), a Greek name (alpha), RR/NN/…, or a function
 *   name before "(" (sin(). Operators (= < > ^ _ \ ∈ …) always start a formula
 *   and take the letter in front of them along. Space leaves a formula; inside a
 *   sub- or superscript it first leaves the script. "$" switches by hand.
 *
 * Everything is done through MathLive's model, so undo, selection and the
 * caret keep working as usual.
 */

(() => {
  "use strict";

  const LETTER = /^[A-Za-z]$/;
  const WORD_CHAR = /^[A-Za-zÄÖÜäöüß]$/;

  const GREEK = new Set([
    "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta",
    "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau",
    "upsilon", "phi", "varphi", "chi", "psi", "omega",
    "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Phi", "Psi", "Omega",
  ]);
  const NAMED = {
    NN: "\\mathbb{N}", ZZ: "\\mathbb{Z}", QQ: "\\mathbb{Q}", RR: "\\mathbb{R}", CC: "\\mathbb{C}",
    infty: "\\infty", emptyset: "\\emptyset",
  };
  /* Only before "(", "^" or "_": as a word on its own "min" or "Max" is prose. */
  const FUNCTIONS = new Set(["sin", "cos", "tan", "cot", "ln", "log", "exp", "lim", "max", "min",
    "sup", "inf", "det", "dim", "ker", "deg", "gcd", "arg", "sinh", "cosh", "tanh", "arcsin",
    "arccos", "arctan", "sgn"]);

  /* A single letter before "." is usually an abbreviation: z. B., d. h., u. a. */
  const ABBREVIATION_LETTERS = new Set(["z", "d", "u", "s", "o", "v", "i", "e", "b", "h", "a"]);

  /** Keys that always begin a formula. */
  const ALWAYS_MATH = new Set(["=", "<", ">", "^", "_", "\\", "|", "∘", "∈", "∉", "≤", "≥", "≠",
    "→", "⇒", "⇔", "↦", "∀", "∃", "∞", "·", "×", "÷", "≈", "≡", "⊂", "⊆", "∪", "∩", "±"]);
  /** Keys that begin a formula only next to maths: "x + 1" but "Aufgaben-Blatt". */
  const NEAR_MATH = new Set(["+", "-", "*", "/"]);
  const PUNCTUATION = new Set([",", ";", ":", "!", "?", "."]);
  /** Closing a script early: "x_1, x_2" must not put ", x_2" into the index. */
  const LEAVES_SCRIPT = new Set([",", ";", ":", "=", "<", ">", "."]);
  const OPERATOR_TYPES = new Set(["mrel", "mbin", "mopen", "mpunct", "mop"]);
  const OPENERS = new Set(["(", "[", "|"]);

  const modelOf = (mf) => mf._mathfield?.model ?? null;

  /** Fields where "$" asked for maths by hand; typing is not switched back. */
  const manualMath = new WeakSet();

  const isText = (atom) => atom && atom.type === "text";
  const isSpace = (atom) => isText(atom) && atom.value === " ";
  const isMath = (atom) => atom && atom.mode === "math" && atom.type !== "first";

  /** What sits left of the caret on the top level: "…before␣word␣␣|". */
  function context(mf, model) {
    const caret = mf.position;
    let atom = model.at(caret);
    const spaces = [];
    while (isSpace(atom)) {
      spaces.unshift(atom);
      atom = atom.leftSibling;
    }
    const word = [];
    while (isText(atom) && WORD_CHAR.test(atom.value)) {
      word.unshift(atom);
      atom = atom.leftSibling;
    }
    // Brackets glued to the front of a word go with it: "(a" becomes maths whole.
    const openers = [];
    if (word.length) {
      while (isText(atom) && OPENERS.has(atom.value)) {
        openers.unshift(atom);
        atom = atom.leftSibling;
      }
    }
    // Blanks between an operator and the word: "x = y" needs none of them.
    let start = atom;
    if (word.length) {
      let lead = atom;
      let blanks = 0;
      while (isSpace(lead)) {
        lead = lead.leftSibling;
        blanks += 1;
      }
      if (blanks && isMath(lead) && OPERATOR_TYPES.has(lead.type)) start = lead;
    }
    // A little of the prose before, for abbreviations.
    let textBefore = "";
    for (let a = atom, n = 0; isText(a) && n < 4; a = a.leftSibling, n += 1) textBefore = a.value + textBefore;
    return {
      caret,
      spaces,
      textBefore,
      word: word.map((a) => a.value).join(""),
      openers: openers.map((a) => a.value).join(""),
      before: atom,
      startOfWord: model.offsetOf(atom),
      startOfWordAndBlanks: model.offsetOf(start),
      startOfSpaces: spaces.length ? model.offsetOf(spaces[0].leftSibling) : caret,
    };
  }

  /** The LaTeX a finished word stands for, or `null` if it is prose.
      `textBefore` is the prose just before the word, for "z. B." and friends. */
  function latexFor(word, trigger, textBefore = "") {
    if (!word) return null;
    if (LETTER.test(word)) {
      if (trigger === "." && (ABBREVIATION_LETTERS.has(word) || /(^|\s)[A-Za-z]\.\s?$/.test(textBefore))) {
        return null;
      }
      return word;
    }
    if (GREEK.has(word)) return `\\${word}`;
    if (NAMED[word]) return NAMED[word];
    if (FUNCTIONS.has(word) && (trigger === "(" || trigger === "^" || trigger === "_")) return `\\${word}`;
    return null;
  }

  function replaceRange(mf, from, to, latex) {
    mf.selection = { ranges: [[from, to]], direction: "forward" };
    if (latex) {
      mf.insert(latex, { format: "latex", insertionMode: "replaceSelection", selectionMode: "after", mode: "math" });
    } else {
      mf.executeCommand("deleteBackward");
    }
  }

  const switchTo = (mf, mode) => {
    if (mf.mode !== mode) mf.executeCommand(["switchMode", mode]);
  };

  /** Turns the word left of the caret into maths if it is one, and drops
      blanks between a formula and the caret. */
  function convertWord(mf, model, trigger) {
    const ctx = context(mf, model);
    const latex = latexFor(ctx.word, trigger, ctx.textBefore);
    if (latex) {
      replaceRange(mf, ctx.startOfWordAndBlanks, ctx.caret, ctx.openers + latex);
      return true;
    }
    if (ctx.spaces.length && !ctx.word && isMath(ctx.before)) {
      replaceRange(mf, ctx.startOfSpaces, ctx.caret, "");
      return true;
    }
    return false;
  }

  const stop = (e) => {
    e.preventDefault();
    e.stopPropagation();
  };

  function onTextKey(e, mf, model, key) {
    const ctx = context(mf, model);

    if (key === " ") {
      if (ctx.spaces.length) {
        stop(e); // one space is enough; TeX would swallow the second anyway
        return true;
      }
      if (latexFor(ctx.word, " ")) {
        convertWord(mf, model, " ");
        switchTo(mf, "text");
      }
      return false; // MathLive types the space
    }

    if (key === "$") {
      stop(e);
      convertWord(mf, model, "$");
      switchTo(mf, "math");
      manualMath.add(mf);
      return true;
    }

    if (key === "!" && !ctx.spaces.length
        && ((ctx.word && LETTER.test(ctx.word)) || (!ctx.word && isMath(ctx.before)))) {
      // n! is a factorial, not an exclamation.
      convertWord(mf, model, key);
      switchTo(mf, "math");
      return false;
    }

    if (PUNCTUATION.has(key)) {
      if (!ctx.spaces.length && latexFor(ctx.word, key, ctx.textBefore)) {
        convertWord(mf, model, key);
        switchTo(mf, "text");
      }
      return false;
    }

    if (key === "(") {
      const glued = !ctx.spaces.length && latexFor(ctx.word, "(");
      const afterMath = !ctx.word && isMath(ctx.before)
        && (!ctx.spaces.length || OPERATOR_TYPES.has(ctx.before.type));
      if (glued || afterMath) {
        convertWord(mf, model, "(");
        switchTo(mf, "math");
      }
      return false;
    }

    if (key === "=" && !ctx.spaces.length && isText(ctx.before) && ctx.before.value === ":" && !ctx.word) {
      // ":=" — the colon typed as prose belongs to the definition sign.
      const colon = ctx.before;
      let start = colon.leftSibling;
      while (isSpace(start)) start = start.leftSibling;
      const from = isMath(start) ? model.offsetOf(start) : model.offsetOf(colon.leftSibling);
      replaceRange(mf, from, ctx.caret, ":");
      switchTo(mf, "math");
      return false;
    }

    if (ALWAYS_MATH.has(key)) {
      convertWord(mf, model, key);
      switchTo(mf, "math");
      return false;
    }

    if (NEAR_MATH.has(key)) {
      const nextToMath = latexFor(ctx.word, key) || (!ctx.word && isMath(ctx.before));
      if (nextToMath) {
        convertWord(mf, model, key);
        switchTo(mf, "math");
      }
      return false;
    }

    if (/^\d$/.test(key)) {
      // "x = 2": a number right after an operator is part of the formula.
      if (!ctx.word && isMath(ctx.before) && (!ctx.spaces.length || OPERATOR_TYPES.has(ctx.before.type))) {
        convertWord(mf, model, key);
        switchTo(mf, "math");
      }
      return false;
    }

    return false;
  }

  function onMathKey(e, mf, model, key) {
    const here = model.at(mf.position);
    const atRoot = here.parent === model.root;

    if (!atRoot) {
      const branch = here.parentBranch;
      const inScript = branch === "subscript" || branch === "superscript";
      if (key === " ") {
        stop(e);
        // A script or a typed a/b denominator ends at the blank; a numerator,
        // a root or a bracket keeps it as TeX spacing.
        if (!inScript && branch !== "below") return true;
        leaveGroup(mf, model);
        if (model.at(mf.position).parent === model.root && !manualMath.has(mf)) typeSpace(mf, model);
        return true;
      }
      if (inScript && LEAVES_SCRIPT.has(key) && scriptLength(here) >= 1) {
        mf.executeCommand("moveAfterParent");
      }
      return false;
    }

    if (key === " ") {
      stop(e);
      // Inside $…$ blanks are TeX's business.
      if (!manualMath.has(mf)) typeSpace(mf, model);
      return true;
    }
    if (key === "$") {
      stop(e);
      manualMath.delete(mf);
      switchTo(mf, "text");
      return true;
    }
    return false;
  }

  /* Leaves the script or denominator the caret is in. Sentence punctuation typed
     at its very end ("… = a/2.") belongs after it, not in it. */
  function leaveGroup(mf, model) {
    const last = model.at(mf.position);
    const punctuation = last && last.mode === "math" && [".", ","].includes(last.value) && last.leftSibling?.type !== "first"
      ? last.value
      : null;
    if (punctuation) mf.executeCommand("deleteBackward");
    mf.executeCommand("moveAfterParent");
    if (punctuation) mf.insert(punctuation, { format: "latex", mode: "math", selectionMode: "after" });
  }

  /** `{` and `}` in a sub- or superscript group and ungroup instead of drawing
      braces — "x_{n+1}" typed the LaTeX way. Used by formula lines too. */
  function scriptBraces(e, mf) {
    const model = modelOf(mf);
    if (!model || e.metaKey || e.ctrlKey || !mf.selectionIsCollapsed) return false;
    if (e.key !== "{" && e.key !== "}") return false;
    const here = model.at(mf.position);
    const branch = here?.parentBranch;
    if (branch !== "subscript" && branch !== "superscript") return false;
    if (e.key === "{" && here.type !== "first") return false;
    stop(e);
    if (e.key === "}") mf.executeCommand("moveAfterParent");
    return true;
  }

  /** How many atoms the script the caret is in holds. */
  function scriptLength(atom) {
    let count = 0;
    let a = atom;
    while (a && a.type !== "first") {
      count += 1;
      a = a.leftSibling;
    }
    return count;
  }

  /** Leaves the formula with a real space, unless one is already there. */
  function typeSpace(mf, model) {
    manualMath.delete(mf);
    if (!isSpace(model.at(mf.position))) {
      mf.insert("\\text{ }", { format: "latex", selectionMode: "after" });
    }
    switchTo(mf, "text");
  }

  /**
   * Keydown in a mixed field, before MathLive sees it. Returns `true` when the
   * key was fully handled; otherwise MathLive processes it afterwards, in the
   * mode set here.
   */
  function keydown(e, mf) {
    if (e.metaKey || e.ctrlKey || e.isComposing) return false;
    const model = modelOf(mf);
    if (!model || !mf.selectionIsCollapsed) return false;

    const key = e.key === "Dead" && e.code === "Backquote" ? "^" : e.key;
    if (key.length !== 1) return false;
    if (scriptBraces(e, mf)) return true;

    try {
      // A mixed line is written as text: at its very start, and wherever the
      // caret sits right after text, typing continues as text.
      const left = model.at(mf.position);
      if (mf.mode === "math" && left.parent === model.root && !manualMath.has(mf)
          && (left.type === "first" || isText(left))) {
        switchTo(mf, "text");
      }
      if (mf.mode === "text") {
        const here = model.at(mf.position);
        if (here.parent !== model.root) return false;
        return onTextKey(e, mf, model, key);
      }
      if (mf.mode === "math") return onMathKey(e, mf, model, key);
    } catch (error) {
      // A rule that trips over an unexpected structure must never eat the key.
      window.webkit?.messageHandlers?.mathpad?.postMessage({
        name: "log", payload: { text: `mixed input: ${error.message}` },
      });
    }
    return false;
  }

  /** Called when the caret leaves the line: the last word is finished too. */
  function finish(mf) {
    const model = modelOf(mf);
    if (!model || !mf.selectionIsCollapsed) return false;
    if (mf.mode === "math") {
      const here = model.at(mf.position);
      const branch = here.parentBranch;
      if (here.parent?.parent === model.root && ["subscript", "superscript", "below"].includes(branch)
          && [".", ","].includes(here.value)) {
        try { leaveGroup(mf, model); } catch (_) { /* leave it */ }
      }
      return false;
    }
    if (mf.mode !== "text") return false;
    if (model.at(mf.position).parent !== model.root) return false;
    try {
      const ctx = context(mf, model);
      if (!ctx.spaces.length && latexFor(ctx.word, "end")) {
        return convertWord(mf, model, "end");
      }
    } catch (_) { /* leave the line as it is */ }
    return false;
  }

  /* Plain text pasted without any markup ("Sei x > 0 und f(x) = x^2") gets the
     same reading as typing it would: words stay words, formulas become LaTeX. */
  function classifyPlain(text) {
    const runs = [];
    let math = [];
    const words = (chunk) => runs.push({ t: "text", text: chunk, bold: false, italic: false });
    const flush = () => {
      const trailing = [];
      while (math.length && /^\s+$/.test(math.at(-1))) trailing.unshift(math.pop());
      const source = math.join("").trim();
      math = [];
      if (source) {
        let latex = source;
        try {
          latex = window.MathLive?.convertAsciiMathToLatex?.(source) || source;
        } catch (_) { /* keep the source */ }
        runs.push({ t: "math", latex });
      }
      if (trailing.length) words(trailing.join(""));
    };

    for (const token of text.split(/(\s+)/)) {
      if (!token) continue;
      if (/^\s+$/.test(token)) {
        if (math.length) math.push(token);
        else words(token);
        continue;
      }
      const bare = token.replace(/[.,;:!?]+$/, "");
      const trail = token.slice(bare.length);
      const mathy = bare !== "" && (
        latexFor(bare, " ") !== null
        || /[=<>^_∘∈∉≤≥≠→⇒⇔↦·×÷≈≡⊂⊆∪∩±\\]/.test(bare)
        || (/[+\-*/()]/.test(bare) && !/[A-Za-zÄÖÜäöüß]{3,}/.test(bare))
        || (/^\d+([.,]\d+)?$/.test(bare) && math.length > 0)
      );
      if (mathy) {
        math.push(bare);
        if (trail) {
          flush();
          words(trail);
        }
      } else {
        flush();
        words(token);
      }
    }
    flush();
    return runs;
  }

  /* MathLive writes an exclamation mark typed as prose as "\!" — which LaTeX
     reads as a negative thin space. MathLive itself reads both back as "!", so
     the stored value simply gets the plain character. */
  function normalizeLatex(latex) {
    if (!latex || !latex.includes("\\!")) return latex;
    let out = "";
    const textDepths = [];
    let depth = 0;
    for (let i = 0; i < latex.length; i += 1) {
      const rest = latex.slice(i);
      const opener = /^\\(text|textbf|textit|textrm|textsf|texttt|mbox)\{/.exec(rest);
      if (opener) {
        out += opener[0];
        i += opener[0].length - 1;
        depth += 1;
        textDepths.push(depth);
        continue;
      }
      const ch = latex[i];
      if (ch === "\\" && latex[i + 1] === "!" && textDepths.length) {
        out += "!";
        i += 1;
        continue;
      }
      if (ch === "\\" && i + 1 < latex.length) {
        out += ch + latex[i + 1];
        i += 1;
        continue;
      }
      if (ch === "{") depth += 1;
      if (ch === "}") {
        if (textDepths.at(-1) === depth) textDepths.pop();
        depth -= 1;
      }
      out += ch;
    }
    return out;
  }

  window.MixedInput = { keydown, finish, classifyPlain, latexFor, scriptBraces, normalizeLatex };
})();
