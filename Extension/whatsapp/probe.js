// Reports the STRUCTURE of a WhatsApp Web tab, so the reader's selectors can be checked against the live page. It
// returns tag names, attribute names, counts, and the class of each id-like value. It never returns a name, a number,
// an id, a message, an attribute value or any text. Paste this file in the DevTools console of the tab, then run
//   copy(JSON.stringify(WorkbenchWhatsAppProbe.run(document), null, 1))
// It reads the page and changes nothing. It is not part of the extension.
(() => {
  const headerSelectors = ["#main header", "header"];
  const panelSelectors = [
    "#app [role='complementary']",
    "#app section",
    "[data-testid*='drawer']",
    "[data-testid*='info']",
    "[aria-label*='nfo']",
  ];
  const messageSelector = "#main [data-id]";
  const roleNames = new Set(["listitem", "list", "button", "heading", "complementary", "region", "dialog", "img", "row", "grid"]);
  const maxCarriers = 40;

  const jidShape = "\\d+(?:[-:]\\d+)?@";
  const patterns = [
    ["phone-shaped jid", new RegExp(`^\\d+(?:-\\d+)?@(?:c\\.us|s\\.whatsapp\\.net)$`)],
    ["lid", new RegExp(`^\\d+(?::\\d+)?@lid$`)],
    ["group jid", new RegExp(`^\\d+(?:-\\d+)?@g\\.us$`)],
    ["message id with phone-shaped sender", new RegExp(`^(?:true|false)_.+_[A-Za-z0-9-]+_${jidShape}(?:c\\.us|s\\.whatsapp\\.net)$`)],
    ["message id with lid sender", new RegExp(`^(?:true|false)_.+_[A-Za-z0-9-]+_${jidShape}lid$`)],
    ["message id with no sender", new RegExp(`^(?:true|false)_${jidShape}(?:c\\.us|s\\.whatsapp\\.net|g\\.us|lid)_[A-Za-z0-9-]+$`)],
    ["text that holds an id", new RegExp(`${jidShape}(?:c\\.us|s\\.whatsapp\\.net|g\\.us|lid)`)],
  ];

  const classOfValue = (value) => patterns.find(([, pattern]) => pattern.test(value))?.[0] ?? "no id";

  // A name the page chose (an attribute or a custom tag) can carry data, such as a number. Only a short name with no run
  // of 4 digits is reported.
  const safeName = (name) =>
    /^[a-z][a-z0-9:_-]{0,39}$/i.test(name) && !/\d{4}/.test(name) ? name.toLowerCase() : "(odd name)";

  const bump = (counts, key) => {
    counts[key] = (counts[key] ?? 0) + 1;
  };

  const path = (element, root) => {
    const tags = [];
    for (let node = element; node && node !== root && tags.length < 6; node = node.parentElement) {
      tags.unshift(safeName(node.localName));
    }
    return tags.join(">");
  };

  // The structure of one subtree: tags, attribute names, and the class of each attribute value.
  function structureOf(root) {
    const tags = {};
    const attributeNames = {};
    const idClasses = {};
    const roles = {};
    const carriers = new Map();
    let hasText = false;
    let countLikeText = 0;
    for (const element of [root, ...root.querySelectorAll("*")]) {
      bump(tags, safeName(element.localName));
      for (const attribute of element.attributes) {
        const name = safeName(attribute.name);
        bump(attributeNames, name);
        const valueClass = classOfValue(attribute.value);
        if (valueClass === "no id") continue;
        bump(idClasses, `${name} | ${valueClass}`);
        const key = `${path(element, root)} | ${name} | ${valueClass}`;
        carriers.set(key, (carriers.get(key) ?? 0) + 1);
      }
      const role = element.getAttribute("role");
      if (role && roleNames.has(role)) bump(roles, role);
      const ownText = [...element.childNodes].filter((node) => node.nodeType === 3).map((node) => node.textContent.trim()).join("");
      if (ownText) hasText = true;
      if (/^\D{0,30}\d{1,6}\D{0,30}$/.test(ownText)) countLikeText += 1;
    }
    return {
      elements: Object.values(tags).reduce((sum, count) => sum + count, 0),
      tags,
      attributeNames,
      idClasses,
      roles,
      hasText,
      elementsWithCountLikeText: countLikeText,
      carriers: [...carriers].slice(0, maxCarriers).map(([key, count]) => {
        const [where, attribute, valueClass] = key.split(" | ");
        return { path: where, attribute, class: valueClass, count };
      }),
    };
  }

  function firstMatch(doc, selectors) {
    return selectors.flatMap((selector) => {
      const element = doc.querySelector(selector);
      return element ? [{ selector, structure: structureOf(element) }] : [];
    });
  }

  function messageRows(doc) {
    const rows = [...doc.querySelectorAll(messageSelector)];
    const idClasses = {};
    for (const row of rows) bump(idClasses, classOfValue(row.getAttribute("data-id") ?? ""));
    return { count: rows.length, idClasses };
  }

  function idCarriersAnywhere(doc) {
    const found = new Map();
    for (const element of doc.body.querySelectorAll("*")) {
      for (const attribute of element.attributes) {
        const valueClass = classOfValue(attribute.value);
        if (valueClass === "no id" || valueClass.startsWith("message id")) continue;
        const key = `${path(element, doc.body)} | ${safeName(attribute.name)} | ${valueClass}`;
        found.set(key, (found.get(key) ?? 0) + 1);
      }
    }
    return [...found].slice(0, maxCarriers).map(([key, count]) => {
      const [where, attribute, valueClass] = key.split(" | ");
      return { path: where, attribute, class: valueClass, count };
    });
  }

  function run(doc) {
    return {
      version: 1,
      header: firstMatch(doc, headerSelectors),
      panels: firstMatch(doc, panelSelectors),
      messageRows: messageRows(doc),
      idCarriersOutsideMessages: idCarriersAnywhere(doc),
    };
  }

  globalThis.WorkbenchWhatsAppProbe = { run };
})();
