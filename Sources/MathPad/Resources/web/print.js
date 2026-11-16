/* MathPad — the sheet laid out for paper.
 *
 * The editor shows every formula line in a MathLive field, and a field cannot
 * wrap: a long "Text + Formel" line simply ran off the right edge of the PDF.
 * For export the sheet is therefore set again as ordinary flowing text — prose
 * as prose, each formula as static MathLive markup — so a long sentence breaks
 * between words like any sentence. Only a single formula that is wider than the
 * page on its own is scaled down to fit.
 *
 * `build` lays the sheet out at a fixed page width and reports where pages may
 * break; Swift cuts the result into A4 pages.
 */

(() => {
  "use strict";

  const escapeHTML = (text) =>
    text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  /** Index of the brace closing the one at `open`, or -1. */
  function closingBrace(src, open) {
    let depth = 0;
    for (let i = open; i < src.length; i += 1) {
      const ch = src[i];
      if (ch === "\\") { i += 1; continue; }
      if (ch === "{") depth += 1;
      if (ch === "}") {
        depth -= 1;
        if (depth === 0) return i;
      }
    }
    return -1;
  }

  // ------------------------------------------------------------ formulas

  /** Set by `build`: the editor's repairs for LaTeX MathLive misreads. */
  let repair = (latex) => latex;

  function mathHTML(latex) {
    const source = repair(latex.trim());
    if (!source) return "";
    try {
      return `<span class="print-math">${window.MathLive.convertLatexToMarkup(source)}</span>`;
    } catch (_) {
      return `<span class="print-math print-raw">${escapeHTML(source)}</span>`;
    }
  }

  // ------------------------------------------------------------ prose inside LaTeX

  const TEXT_GROUP = /^\\(text|textbf|textit|textrm|textsf|texttt|textup|textnormal|textsl|mbox|emph|underline)\{/;

  const TEXT_ESCAPES = [
    [/^\\textbackslash(\{\})?/, "\\"], [/^\\textasciitilde(\{\})?/, "~"],
    [/^\\textasciicircum(\{\})?/, "^"], [/^\\ldots(\{\})?/, "…"], [/^\\dots(\{\})?/, "…"],
    [/^\\ss(\{\})?/, "ß"], [/^\\euro(\{\})?/, "€"], [/^\\lbrack(\{\})?/, "["],
    [/^\\rbrack(\{\})?/, "]"], [/^\\textbraceleft(\{\})?/, "{"], [/^\\textbraceright(\{\})?/, "}"],
    [/^\\S(\{\})?/, "§"], [/^\\copyright(\{\})?/, "©"], [/^\\quad/, "\u2003"], [/^\\qquad/, "\u2003\u2003"],
    [/^\\[{}&%#$_!,;: ]/, null],
    [/^''/, "”"], [/^``/, "“"], [/^~/, "\u00a0"],
  ];

  /**
   * The content of a \text-like group as HTML that wraps like prose. Styling
   * commands nest into tags; anything unexpected is handed to MathLive so it
   * still shows up rather than as raw LaTeX.
   */
  function textHTML(src) {
    let out = "";
    let i = 0;
    while (i < src.length) {
      const rest = src.slice(i);

      const group = TEXT_GROUP.exec(rest);
      if (group) {
        const open = i + group[0].length - 1;
        const close = closingBrace(src, open);
        if (close < 0) break;
        const inner = textHTML(src.slice(open + 1, close));
        const tag = { textbf: "b", textit: "i", textsl: "i", emph: "i", underline: "u", texttt: "code" }[group[1]];
        out += tag ? `<${tag}>${inner}</${tag}>` : inner;
        i = close + 1;
        continue;
      }

      const colour = /^\\(textcolor|colorbox)\{([^{}]*)\}\{/.exec(rest);
      if (colour) {
        const open = i + colour[0].length - 1;
        const close = closingBrace(src, open);
        if (close < 0) break;
        const value = colour[2].replace(/[^#a-zA-Z0-9]/g, "");
        const property = colour[1] === "colorbox" ? "background-color" : "color";
        out += `<span style="${property}:${value}">${textHTML(src.slice(open + 1, close))}</span>`;
        i = close + 1;
        continue;
      }

      const inlineMath = /^\$([^$]*)\$/.exec(rest);
      if (inlineMath) {
        out += mathHTML(inlineMath[1]);
        i += inlineMath[0].length;
        continue;
      }

      let matched = false;
      for (const [pattern, replacement] of TEXT_ESCAPES) {
        const m = pattern.exec(rest);
        if (!m) continue;
        const shown = replacement ?? ({ "\\ ": " ", "\\!": "!", "\\,": "\u2009", "\\;": " ", "\\:": " " }[m[0]] ?? m[0].slice(1));
        out += escapeHTML(shown);
        i += m[0].length;
        matched = true;
        break;
      }
      if (matched) continue;

      if (rest[0] === "{") {
        const close = closingBrace(src, i);
        if (close < 0) break;
        out += textHTML(src.slice(i + 1, close));
        i = close + 1;
        continue;
      }

      const command = /^\\[a-zA-Z]+/.exec(rest);
      if (command) {
        // Some command inside prose (an accent, a symbol): let MathLive draw it.
        let end = i + command[0].length;
        if (src[end] === "{") {
          const close = closingBrace(src, end);
          if (close > 0) end = close + 1;
        }
        out += mathHTML(`\\text{${src.slice(i, end)}}`);
        i = end;
        continue;
      }

      out += escapeHTML(rest[0]);
      i += 1;
    }
    return out;
  }

  /**
   * A mixed line as a paragraph: its top-level \text groups become prose, the
   * rest formulas. Groups nested inside a formula (a \text in a fraction) stay
   * part of that formula.
   */
  function mixedHTML(latex) {
    let out = "";
    let math = "";
    let i = 0;
    const flushMath = () => {
      if (math.trim()) out += mathHTML(math);
      else if (math) out += " ";
      math = "";
    };

    while (i < latex.length) {
      const rest = latex.slice(i);
      const group = TEXT_GROUP.exec(rest) || /^\\(textcolor|colorbox)\{[^{}]*\}\{\\text/.exec(rest);
      if (group) {
        let end;
        if (group[1] === "textcolor" || group[1] === "colorbox") {
          const open = latex.indexOf("{", latex.indexOf("}", i) + 1);
          end = closingBrace(latex, open);
        } else {
          end = closingBrace(latex, i + group[0].length - 1);
        }
        if (end < 0) {
          math += rest;
          break;
        }
        flushMath();
        out += textHTML(latex.slice(i, end + 1));
        i = end + 1;
        continue;
      }
      if (rest[0] === "\\") {
        const command = /^\\([a-zA-Z]+|.)/.exec(rest);
        math += command[0];
        i += command[0].length;
        continue;
      }
      if (rest[0] === "{") {
        const end = closingBrace(latex, i);
        if (end < 0) {
          math += rest;
          break;
        }
        math += latex.slice(i, end + 1);
        i = end + 1;
        continue;
      }
      math += rest[0];
      i += 1;
    }
    flushMath();
    return out;
  }

  // ------------------------------------------------------------ tables

  function tableHTML(value) {
    let data = null;
    try { data = JSON.parse(value); } catch (_) { /* empty table below */ }
    const rows = Array.isArray(data?.rows) ? data.rows.filter(Array.isArray) : [];
    if (!rows.length) return "";
    const cols = Math.max(...rows.map((r) => r.length));
    const style = ["grid", "lines", "none"].includes(data.style) ? data.style : "grid";
    const align = Array.isArray(data.align) ? data.align : [];
    const widths = Array.isArray(data.widths) ? data.widths : [];

    let html = `<table class="mp-table print-table lines-${style}${data.header ? " has-header" : ""}"><colgroup>`;
    for (let c = 0; c < cols; c += 1) {
      html += widths[c] > 0 ? `<col style="width:${Number(widths[c])}em">` : "<col>";
    }
    html += "</colgroup><tbody>";
    rows.forEach((row) => {
      html += "<tr>";
      for (let c = 0; c < cols; c += 1) {
        const a = ["left", "center", "right"].includes(align[c]) ? align[c] : "left";
        html += `<td class="align-${a}"><div class="print-cell">${mixedHTML(row[c] || "")}</div></td>`;
      }
      html += "</tr>";
    });
    return `${html}</tbody></table>`;
  }

  // ------------------------------------------------------------ layout

  function blockHTML(block, sanitize) {
    const value = block.value || "";
    switch (block.kind) {
      case "math":
        return `<div class="print-line print-display">${mathHTML(value)}</div>`;
      case "mixed":
        return `<div class="print-line print-mixed">${mixedHTML(value)}</div>`;
      case "table":
        return `<div class="print-line print-table-wrap">${tableHTML(value)}</div>`;
      case "paragraph":
      case "text":
      case "heading": {
        const looksLikeMarkup = value.includes("<") || value.includes("&");
        const body = looksLikeMarkup ? sanitize(value) : escapeHTML(value);
        return `<div class="print-line prose ${block.kind}">${body}</div>`;
      }
      default:
        return `<div class="print-line print-mixed">${escapeHTML(value)}</div>`;
    }
  }

  /** Scales a formula (or table) down until it fits the width it has. */
  function fitWidth(element, available) {
    element.style.zoom = "";
    const natural = element.scrollWidth;
    if (natural > available + 1) {
      element.style.zoom = String(Math.max(0.2, available / natural));
    }
  }

  /* Not requestAnimationFrame: the export's web view is never on screen, and an
     invisible view gets no animation frames — the promise would never settle.
     Reading sizes forces layout anyway; the pause only lets fonts settle. */
  const nextFrame = () => new Promise((resolve) => setTimeout(resolve, 30));

  /** Lines of a paragraph as their bottom edges, for breaking between them. */
  function lineBottoms(element, offset) {
    const range = document.createRange();
    range.selectNodeContents(element);
    // Every word and formula is its own rectangle; rectangles that overlap
    // vertically sit on the same line, and a line ends at its lowest one.
    const rects = [...range.getClientRects()].filter((r) => r.height > 0).sort((a, b) => a.top - b.top);
    const lines = [];
    for (const rect of rects) {
      const line = lines[lines.length - 1];
      if (line && rect.top < line.bottom - 2) line.bottom = Math.max(line.bottom, rect.bottom);
      else lines.push({ bottom: rect.bottom });
    }
    return lines.map((line) => Math.round(line.bottom + offset));
  }

  /**
   * Lays the blocks out at `width` CSS pixels and returns the total height and,
   * per block, its top and bottom plus the places inside it where a page may
   * break (between lines of prose, between table rows).
   */
  async function build(blocks, { width, sanitize, repairLatex }) {
    if (repairLatex) repair = repairLatex;
    document.documentElement.classList.add("exporting", "printing");
    document.documentElement.dataset.theme = "light";

    let root = document.getElementById("print");
    if (!root) {
      root = document.createElement("div");
      root.id = "print";
      document.body.appendChild(root);
    }
    root.style.width = `${width}px`;
    const visible = blocks.filter((b) => {
      const v = (b.value || "").replace(/<[^>]*>/g, "").trim();
      return v.length > 0;
    });
    root.innerHTML = visible.map((b) => blockHTML(b, sanitize)).join("");

    // Fonts first: every measurement below depends on them.
    try {
      await Promise.race([document.fonts.ready, new Promise((resolve) => setTimeout(resolve, 3000))]);
    } catch (_) { /* measure anyway */ }
    await nextFrame();
    await nextFrame();

    for (const line of root.querySelectorAll(".print-display, .print-table-wrap")) {
      const inner = line.firstElementChild;
      if (inner) fitWidth(inner, line.clientWidth);
    }
    for (const math of root.querySelectorAll(".print-mixed > .print-math, .print-cell > .print-math")) {
      fitWidth(math, math.parentElement.clientWidth);
    }
    await nextFrame();

    const offset = window.scrollY;
    const layout = [];
    for (const line of root.children) {
      const rect = line.getBoundingClientRect();
      const breaks = [];
      if (line.classList.contains("print-table-wrap")) {
        for (const tr of line.querySelectorAll("tr")) breaks.push(Math.round(tr.getBoundingClientRect().bottom + offset));
      } else if (!line.classList.contains("print-display")) {
        breaks.push(...lineBottoms(line, offset));
      }
      layout.push({
        top: Math.round(rect.top + offset),
        bottom: Math.round(rect.bottom + offset),
        breaks,
      });
    }
    return {
      width,
      height: Math.ceil(root.getBoundingClientRect().bottom + offset),
      blocks: layout,
    };
  }

  window.MathPrint = { build, mixedHTML, textHTML };
})();
