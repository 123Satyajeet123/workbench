// Reads one page, or one frame, into what the app gets: the shown text, and the lines that carry the page's own ids.
//   text       the shown text, as the generic reader gives it.
//   container  the place the ids belong to, { value, via }, or null.
//   items      lines { id, via, text }. An id and a via are null when no source gave one. With no record for the site, the
//              lines are the generic blocks and have no id. When the record's shape is stale there are no lines.
//   shape      { site, stale } when a record applies to this page, else null.
(() => {
  const { generic, interpret } = globalThis.WorkbenchReader;

  function withoutIds(blocks) {
    return blocks.map(({ text }) => ({ id: null, via: null, text }));
  }

  function withinBudget(items) {
    let length = 0;
    return items.filter(({ text }) => (length += text.length) <= generic.maximumCharacters);
  }

  function readPage({ doc, location, view, records }) {
    const blocks = generic.readBlocks(doc.body, view);
    const text = blocks.map((block) => block.text).join("\n").slice(0, generic.maximumCharacters);
    const unnamed = { text, container: null, items: withoutIds(blocks), shape: null };
    const record = interpret.recordFor(records, location.hostname);
    if (!record) return unnamed;
    const shape = interpret.checkShape(record, doc, location);
    if (!shape.applies) return unnamed;
    const report = { site: record.site, stale: shape.stale };
    if (shape.stale) return { text, container: null, items: [], shape: report };
    const { container, items } = interpret.read(record, doc, location);
    const lines = items.map(({ id, via, element }) => ({ id, via, text: generic.readText(element, view) }));
    return { text, container, items: withinBudget(lines.filter(({ text }) => text)), shape: report };
  }

  globalThis.WorkbenchReader.page = Object.freeze({ readPage });
})();
