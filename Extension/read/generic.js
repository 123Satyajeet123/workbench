// The generic reader: the text a person can see, grouped by the structure that ARIA roles give. It runs in the isolated
// world and shares the page's DOM. It reads text, roles and attributes; it never reads a class name and names no site.
// It only reads: it never clicks, types, focuses or changes anything.
(() => {
  const maximumCharacters = 20000;
  const skipped = "input, textarea, select, [contenteditable=''], [contenteditable='true'], script, style, noscript";
  const implicitRoles = {
    MAIN: "main", UL: "list", OL: "list", LI: "listitem", TR: "row", ARTICLE: "article",
    H1: "heading", H2: "heading", H3: "heading", H4: "heading", H5: "heading", H6: "heading",
  };
  const blockRoles = new Set(["listitem", "row", "article", "heading"]);

  function roleOf(element) {
    return element.getAttribute("role")?.split(/\s+/)[0] || implicitRoles[element.tagName] || null;
  }

  function isRendered(box) {
    return box.width > 0 && box.height > 0;
  }

  function isOnScreen(box, view) {
    return isRendered(box) && box.bottom > 0 && box.right > 0 && box.top < view.height && box.left < view.width;
  }

  // The text nodes under `root` that are shown, in order. With a `view`, only those inside it.
  function* shownTexts(root, view) {
    const walker = root.ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const range = root.ownerDocument.createRange();
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const text = node.textContent.replace(/\s+/g, " ").trim();
      if (!text || !node.parentElement || node.parentElement.closest(skipped)) continue;
      range.selectNodeContents(node);
      const box = range.getBoundingClientRect();
      if (view ? isOnScreen(box, view) : isRendered(box)) yield { text, parent: node.parentElement };
    }
  }

  function blockOf(element) {
    for (let node = element; node; node = node.parentElement) {
      if (blockRoles.has(roleOf(node))) return node;
    }
    return null;
  }

  // The shown text of `root` as blocks in reading order: one block for each run of text inside the same list item, row,
  // article or heading, and one for each run outside them.
  function readBlocks(root, view) {
    const blocks = [];
    let length = 0;
    for (const { text, parent } of shownTexts(root, view)) {
      if (length >= maximumCharacters) break;
      const owner = blockOf(parent);
      const last = blocks.at(-1);
      if (last && last.owner === owner) {
        last.parts.push(text);
      } else {
        blocks.push({ owner, role: owner ? roleOf(owner) : "text", parts: [text] });
      }
      length += text.length + 1;
    }
    return blocks.map(({ role, parts }) => ({ role, text: parts.join("\n") }));
  }

  function readText(root, view) {
    return readBlocks(root, view).map(({ text }) => text).join("\n").slice(0, maximumCharacters);
  }

  globalThis.WorkbenchReader = globalThis.WorkbenchReader ?? {};
  globalThis.WorkbenchReader.generic = Object.freeze({ maximumCharacters, roleOf, readBlocks, readText });
})();
