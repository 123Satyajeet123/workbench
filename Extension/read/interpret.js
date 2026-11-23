// The one interpreter of the adapter records in records.js. It finds a record by host, finds the items and the place
// they are in, and gives each an id from the first source that holds one. It counts the attributes a record expects
// (the shape contract). It selects only by attribute name: never by class, and it names no site.
(() => {
  const attributeName = /^(?!class$)[A-Za-z][A-Za-z0-9_-]*$/i;
  const tagName = /^[a-z][a-z0-9-]*$/;
  const urlParts = { hash: "hash", path: "pathname" };

  function recordFor(records, hostname) {
    return records.find(({ hosts }) => hosts.includes(hostname)) ?? null;
  }

  function withAttribute(root, name) {
    return attributeName.test(name) ? [...root.querySelectorAll(`[${name}]`)] : [];
  }

  // The elements of one tag name, such as the tag a record names for quoted text. A tag is structure, not a class.
  function withTag(root, tag) {
    return tagName.test(tag) ? [...root.querySelectorAll(tag)] : [];
  }

  function matches(value, pattern) {
    return value !== null && (pattern === undefined || new RegExp(pattern).test(value));
  }

  // The id a pattern captures from `value`: its capture groups joined by "/", or the whole value when it has none.
  function captured(value, pattern) {
    if (value === null || value === undefined) return null;
    if (pattern === undefined) return value || null;
    const found = new RegExp(pattern).exec(value);
    if (!found) return null;
    return (found.length > 1 ? found.slice(1).join("/") : found[0]) || null;
  }

  function fromAttribute({ attribute, pattern }, scope) {
    const elements = scope.element ? [scope.element] : withAttribute(scope.doc, attribute);
    for (const element of elements) {
      const value = captured(element.getAttribute(attribute), pattern);
      if (value) return { value, via: attribute };
    }
    return null;
  }

  function fromUrl({ url, pattern }, scope) {
    const value = captured(scope.location[urlParts[url]] ?? null, pattern);
    return value ? { value, via: "url" } : null;
  }

  // The first source that holds an id, as { value, via }, or null. An id is never made up.
  function identify(sources, scope) {
    for (const source of sources) {
      const found = source.attribute === undefined ? fromUrl(source, scope) : fromAttribute(source, scope);
      if (found) return found;
    }
    return null;
  }

  function outermost(elements) {
    return elements.filter((element) => !elements.some((other) => other !== element && other.contains(element)));
  }

  // The place and the items of the page, in page order: { container, items: [{ id, via, element }] }.
  function read(record, doc, location) {
    const scope = { doc, location };
    const items = outermost(
      withAttribute(doc, record.item.with.attribute).filter((element) =>
        matches(element.getAttribute(record.item.with.attribute), record.item.with.pattern),
      ),
    ).map((element) => {
      const found = identify(record.item.id, { doc, location, element });
      return { id: found?.value ?? null, via: found?.via ?? null, element };
    });
    return { container: identify(record.container, scope), items };
  }

  // Whether the page should have items, and whether each attribute the record expects is on it. A page that should
  // have items and lacks one of them is stale: the site changed its page.
  function checkShape(record, doc, location) {
    const { appliesTo, expect } = record.shape;
    if (!matches(location[urlParts[appliesTo.url]] ?? null, appliesTo.pattern)) return { applies: false, stale: false };
    const counts = expect.map(
      ({ attribute, pattern }) =>
        withAttribute(doc, attribute).filter((element) => matches(element.getAttribute(attribute), pattern)).length,
    );
    return { applies: true, stale: counts.some((count) => count === 0) };
  }

  globalThis.WorkbenchReader = globalThis.WorkbenchReader ?? {};
  globalThis.WorkbenchReader.interpret = Object.freeze({ recordFor, withAttribute, withTag, identify, read, checkShape });
})();
