import type { Act, Chip, Sentence, SentencePart, FactRow, FactSection, FactTag, GridCell, MachineView, OpMark, PageBlock } from "./bridge.generated.ts";
import { el } from "./dom.ts";

export interface MachineActions {
  openCite(ref: string): void;
  openPicker(source: string): void;
  mark(fact: number, mark: OpMark["mark"]): void;
  act(name: Act["name"]): void;
  changeView(block: string, form: Facts["viewBar"]["form"], groupBy: string): void;
  retitle(block: string, text: string): void;
  setting(key: string, value: string): void;
}

type Facts = Extract<MachineView, { kind: "facts" }>;
type Grid = Extract<MachineView, { kind: "grid" }>;
type Picker = Extract<MachineView, { kind: "picker" }>;
type Settings = Extract<MachineView, { kind: "settings" }>;
type Status = Extract<MachineView, { kind: "status" }>;


/** Draws a block of a machine from the data Swift worked out. It adds, counts and fetches nothing. */
export function renderMachine(view: MachineView, standing: Standing, block: string, actions: MachineActions): HTMLElement {
  const root = el("section", `machine machine-${view.kind}${block.startsWith("document.") ? " document" : ""}`, undefined, { "data-standing": standing });
  const words = STANDING_WORDS[standing];
  if (words) root.append(standingLine(words, standing, actions));
  root.append(...partsOf(view, block, actions));
  return root;
}

export type Standing = Extract<PageBlock, { kind: "machine" }>["standing"];

const STANDING_WORDS: Record<Standing, string | undefined> = {
  live: undefined,
  added: "New",
  replacement: "Replaces a block",
  removed: "Will be removed",
};

/** What a proposed block is, and the two answers the person gives to the proposal it belongs to. */
function standingLine(words: string, standing: Standing, actions: MachineActions): HTMLElement {
  const line = el("p", "standing", words);
  if (standing === "live") return line;
  for (const [name, label] of [["accept", "Accept"], ["decline", "Decline"]] as const) {
    const button = el("button", "machine-action", label, { type: "button" });
    button.addEventListener("click", () => actions.act(name));
    line.append(" ", button);
  }
  return line;
}

function partsOf(view: MachineView, block: string, actions: MachineActions): HTMLElement[] {
  switch (view.kind) {
    case "heading":
      return [el("h3", "machine-heading", view.text)];
    case "text":
      return [el("p", "machine-text", view.text), chips(view.cites, actions)];
    case "facts":
      return factsParts(view, block, actions);
    case "grid":
      return [el("h4", "machine-title", view.title), gridTable(view), chips(view.cites, actions)];
    case "picker":
      return pickerParts(view, actions);
    case "status":
      return statusParts(view, actions);
    case "settings":
      return view.sentences.map((sentence) => sentenceOf(sentence, actions));
    case "line":
      return [lineOf(view.text, view.act, actions)];
    case "erased":
      return [el("p", "machine-erased", view.note)];
  }
}

/** A line of words, and after it the one phrase the person may click. */
function lineOf(text: string, act: Act | undefined, actions: MachineActions): HTMLElement {
  const line = el("p", "machine-line", text);
  if (act) {
    const button = el("button", "machine-action", act.label, { type: "button" });
    button.addEventListener("click", () => actions.act(act.name));
    line.append(" ", button);
  }
  return line;
}

/** What the machine says of itself: problems first, then what it reads, what it does now, and its last reading as a toggle. */
function statusParts(view: Status, actions: MachineActions): HTMLElement[] {
  const parts: HTMLElement[] = view.notices.map((notice) => el("p", "machine-notice", notice));
  parts.push(lineOf(view.sentence, view.act, actions));
  if (view.journal.length > 0) {
    const journal = el("details", "journal");
    journal.append(el("summary", undefined, "Last reading"));
    for (const line of view.journal) journal.append(el("p", "machine-line", line));
    parts.push(journal);
  }
  return parts;
}

function chips(cites: Chip[], actions: MachineActions): HTMLElement {
  const row = el("div", "chips");
  for (const cite of cites) {
    const chip = cite.opens ? el("button", "chip chip-open", cite.label, { type: "button" }) : el("span", "chip", cite.label);
    if (cite.opens) chip.addEventListener("click", () => actions.openCite(cite.ref));
    row.append(chip);
  }
  return row;
}

function gridTable(grid: Grid): HTMLElement {
  const table = el("table", "machine-table");
  const head = el("tr");
  for (const name of grid.columns) head.append(el("th", undefined, name));
  table.append(headOf(head));
  const body = el("tbody");
  for (const row of grid.rows) body.append(gridRow(row));
  table.append(body);
  return table;
}

function headOf(row: HTMLElement): HTMLElement {
  const head = el("thead");
  head.append(row);
  return head;
}

function gridRow(cells: GridCell[]): HTMLElement {
  const row = el("tr");
  for (const cell of cells) {
    const td = el("td", `cell cell-${cell.kind}`, cell.text, cell.kind === "words" ? {} : { title: cell.source });
    row.append(td);
  }
  return row;
}

function factsParts(view: Facts, block: string, actions: MachineActions): HTMLElement[] {
  const head = el("div", "machine-head");
  head.append(titleInput(view.title, block, actions), el("span", "supporting", view.countText));
  if (view.needsText !== "") head.append(el("span", "needs-pill", view.needsText));
  head.append(viewChips(view, block, actions));
  const folded = view.tallyColumns.length > 0;
  const body = el("div", `facts facts-${view.layout}${folded ? " facts-folded" : ""}`);
  if (folded && view.layout === "table") body.append(groupTableOrList(view, actions));
  else for (const section of view.sections) body.append(sectionOf(view, section, actions, folded));
  const parts = [head];
  if (view.note !== "") parts.push(el("p", "machine-line", view.note));
  return [...parts, body];
}

/** The heading of a view as words the person retypes; it is sent when they leave it or press Return. */
function titleInput(title: string, block: string, actions: MachineActions): HTMLInputElement {
  const input = el("input", "machine-title title-input", undefined, { type: "text", value: title, "aria-label": "Heading of this view" });
  input.disabled = document.documentElement.dataset["editable"] === "false";
  const fit = () => (input.size = Math.max(4, input.value.length + 1));
  fit();
  input.addEventListener("input", fit);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") input.blur();
  });
  input.addEventListener("change", () => actions.retitle(block, input.value));
  return input;
}

const FORM_WORDS: Record<Facts["viewBar"]["form"], string> = {
  foldedList: "Folded list",
  list: "List",
  table: "Table",
  board: "Board",
  counts: "Counts",
};

/** The form and the grouping of a view as two phrases of its heading line; each opens the values the gate allows. */
function viewChips(view: Facts, block: string, actions: MachineActions): HTMLElement {
  const bar = el("span", "view-chips");
  const { form, forms, groupBy, groups } = view.viewBar;
  if (forms.length > 1) {
    bar.append(el("span", "supporting", "as"), chipMenu(forms, form, (value) => FORM_WORDS[value as typeof form], (value) => actions.changeView(block, value as typeof form, groupBy)));
  }
  if (groups.length > 1 && groupBy !== "") {
    bar.append(el("span", "supporting", "by"), chipMenu(groups, groupBy, (value) => value, (value) => actions.changeView(block, form, value)));
  }
  return bar;
}

/** One phrase that shows its value and, when clicked, lists the other values in the page's own type. */
function chipMenu(values: string[], current: string, words: (value: string) => string, send: (value: string) => void): HTMLElement {
  const menu = el("details", "chip-menu");
  menu.append(el("summary", "chip-pick", words(current)));
  const list = el("div", "chip-list");
  for (const value of values) {
    const option = el("button", value === current ? "chip-option current" : "chip-option", words(value), { type: "button", "data-value": value });
    option.addEventListener("click", () => send(value));
    list.append(option);
  }
  menu.append(list);
  return menu;
}

/** A setting as one sentence: its words, and its values as chips the person edits where they stand. */
function sentenceOf(sentence: Sentence, actions: MachineActions): HTMLElement {
  const node = el("p", "sentence");
  for (const part of sentence.parts) {
    if ("words" in part) node.append(document.createTextNode(part.words));
    else node.append(settingChip(part, actions));
  }
  if (sentence.note !== "") node.append(" ", el("span", "sentence-note", sentence.note));
  if (sentence.act) {
    const act = sentence.act;
    const button = el("button", "machine-action", act.label, { type: "button" });
    button.addEventListener("click", () => actions.act(act.name));
    node.append(" ", button);
  }
  return node;
}

function settingChip(part: Extract<SentencePart, { chip: string }>, actions: MachineActions): HTMLElement {
  if (part.entry === "choice") return chipMenu(part.choices, part.text, (value) => value, (value) => actions.setting(part.chip, value));
  const input = el("input", "setting-chip", undefined, { type: "text", value: part.text, "aria-label": "Value of this setting", inputmode: part.entry === "number" ? "numeric" : "text" });
  input.disabled = document.documentElement.dataset["editable"] === "false";
  const fit = () => (input.size = Math.max(3, input.value.length + 1));
  fit();
  input.addEventListener("input", fit);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") input.blur();
  });
  input.addEventListener("change", () => actions.setting(part.chip, input.value));
  return input;
}

function sectionOf(view: Facts, section: FactSection, actions: MachineActions, folded: boolean): HTMLElement {
  if (view.layout === "counts") {
    const node = el("div", "facts-section");
    node.append(el("span", undefined, section.name === "" ? "Facts" : section.name), el("span", "count", String(section.count)));
    return node;
  }
  if (folded) return groupOf(section, actions);
  const node = el("div", "facts-section");
  if (section.name !== "") node.append(sectionName(section));
  if (view.layout === "table") node.append(factTable(view, section, actions));
  else appendLimited(node, section.rows, view.limit, actions);
  return node;
}

/** The first `limit` facts, and the rest behind one control; every fact when `limit` is 0. */
function appendLimited(node: HTMLElement, rows: FactRow[], limit: number, actions: MachineActions): void {
  const shown = limit > 0 ? rows.slice(0, limit) : rows;
  for (const row of shown) node.append(factLine(row, actions));
  if (shown.length === rows.length) return;
  const more = el("details", "more");
  more.append(el("summary", "more-row", `Show ${rows.length - shown.length} more`));
  for (const row of rows.slice(shown.length)) more.append(factLine(row, actions));
  node.append(more);
}

function sectionName(section: FactSection): HTMLElement {
  const name = el("h5", "facts-name", section.name);
  name.append(el("span", "supporting", ` ${section.count}`));
  return name;
}

/** One section as one row that unfolds: its name, what needs the person, its tally, one line, then its facts. */
function groupOf(section: FactSection, actions: MachineActions): HTMLElement {
  const group = el("details", "group");
  const row = el("summary", "group-row");
  row.append(el("span", "group-name", section.name));
  if (section.needs > 0) row.append(el("span", "needs-pill", `${section.needs} ${section.needs === 1 ? "needs" : "need"} you`));
  row.append(tallyChips(section), el("span", "group-count", String(section.count)));
  const line = el("p", "group-line");
  if (section.summary) {
    line.append(document.createTextNode(section.summary.text), numberChips(section.summary.cites, actions));
  } else {
    line.append(el("span", "supporting", `${section.latestDay} · ${section.latest}`));
  }
  const facts = el("div", "group-facts");
  for (const fact of section.rows) facts.append(factLine(fact, actions));
  group.append(row, line, facts);
  return group;
}

function tallyChips(section: FactSection): HTMLElement {
  const chips = el("span", "group-tally");
  for (const tally of section.tally) {
    if (tally.count > 0) chips.append(el("span", `tag tag-${tally.tone}`, `${tally.value} ${tally.count}`));
  }
  return chips;
}

function numberChips(cites: Chip[], actions: MachineActions): HTMLElement {
  const row = el("span", "chips chips-number");
  cites.forEach((cite, index) => {
    const chip = cite.opens ? el("button", "chip chip-open", String(index + 1), { type: "button", title: cite.label }) : el("span", "chip", String(index + 1), { title: cite.label });
    if (cite.opens) chip.addEventListener("click", () => actions.openCite(cite.ref));
    row.append(chip);
  });
  return row;
}

/**
 * A folded table, or the folded list when the table does not fit. The rule: the table needs its natural width; when
 * that is more than the block has, the Newest column goes first, and when that is still too much the same sections
 * show as folded rows of a list. It is decided again whenever the block changes width.
 */
function groupTableOrList(view: Facts, actions: MachineActions): HTMLElement {
  const wrap = el("div", "group-fit");
  const table = groupTable(view, actions);
  const list = el("div", "group-list-fallback");
  for (const section of view.sections) list.append(groupOf(section, actions));
  wrap.append(table, list);
  const scroller = table;
  const fit = () => {
    wrap.classList.remove("no-newest", "as-list");
    if (scroller.scrollWidth <= scroller.clientWidth + 1) return;
    wrap.classList.add("no-newest");
    if (scroller.scrollWidth <= scroller.clientWidth + 1) return;
    wrap.classList.add("as-list");
  };
  new ResizeObserver(fit).observe(wrap);
  return wrap;
}

/** The sections as the rows of one table: a count for each value, what needs the person, the newest fact. */
function groupTable(view: Facts, actions: MachineActions): HTMLElement {
  const wrap = el("div", "table-wrap");
  const table = el("table", "machine-table group-table");
  const head = el("tr");
  head.append(el("th", undefined, ""));
  for (const value of view.tallyColumns) head.append(el("th", "num", value));
  head.append(el("th", "num", "Needs you"), el("th", "newest", "Newest"));
  table.append(headOf(head));
  for (const section of view.sections) {
    const body = el("tbody", "group-body");
    const row = el("tr", "group-trow");
    const toggle = el("button", "group-toggle", section.name, { type: "button", "aria-expanded": "false" });
    const first = el("td", "group-cell");
    first.append(toggle);
    row.append(first);
    for (const tally of section.tally) row.append(el("td", `num tone-${tally.count > 0 ? tally.tone : "none"}`, tally.count > 0 ? String(tally.count) : "·"));
    row.append(el("td", "num", section.needs > 0 ? String(section.needs) : "·"));
    row.append(el("td", "group-newest", `${section.latestDay} · ${section.latest}`, { title: section.latest }));
    const open = el("tr", "group-open");
    open.hidden = true;
    const cell = el("td", undefined, undefined, { colspan: String(view.tallyColumns.length + 3) });
    for (const fact of section.rows) cell.append(factLine(fact, actions));
    open.append(cell);
    toggle.addEventListener("click", () => {
      open.hidden = !open.hidden;
      toggle.setAttribute("aria-expanded", String(!open.hidden));
    });
    body.append(row, open);
    table.append(body);
  }
  wrap.append(table);
  return wrap;
}

function tagOf(tag: FactTag): HTMLElement {
  return el("span", `tag tag-${tag.tone}`, tag.text);
}

function factLine(row: FactRow, actions: MachineActions): HTMLElement {
  const line = el("div", "fact");
  const words = el("button", "fact-words", undefined, { type: "button" });
  if (row.subject !== "") words.append(el("strong", undefined, row.subject), document.createTextNode(" "));
  words.append(document.createTextNode(row.words));
  words.addEventListener("click", () => actions.openCite(`fact:${row.fact}`));
  const meta = el("span", "fact-meta");
  meta.append(...row.needs.map(tagOf), ...row.tags.map(tagOf));
  if (row.due !== "") meta.append(el("span", "supporting", row.due));
  if (row.state !== "") meta.append(el("span", "supporting", row.state));
  line.append(words, meta, markButtons(row, actions));
  return line;
}

function factTable(view: Facts, section: FactSection, actions: MachineActions): HTMLElement {
  const wrap = el("div", "table-wrap");
  const table = el("table", "machine-table");
  const head = el("tr");
  for (const name of view.columns) head.append(el("th", undefined, name));
  head.append(el("th"));
  table.append(headOf(head));
  const body = el("tbody");
  for (const row of section.rows) {
    const tr = el("tr", "fact");
    for (const cell of row.cells) tr.append(el("td", undefined, cell));
    const marks = el("td", "marks-cell");
    marks.append(markButtons(row, actions));
    tr.append(marks);
    body.append(tr);
  }
  table.append(body);
  wrap.append(table);
  return wrap;
}

const MARK_WORDS: Record<OpMark["mark"], string> = { right: "Right", wrong: "Wrong", done: "Done" };

function markButtons(row: FactRow, actions: MachineActions): HTMLElement {
  const marks = el("span", "marks");
  for (const mark of row.marks) {
    const button = el("button", `mark mark-${mark}`, MARK_WORDS[mark], { type: "button", "aria-label": `Mark this fact ${mark}` });
    button.addEventListener("click", () => actions.mark(row.fact, mark));
    marks.append(button);
  }
  return marks;
}

function pickerParts(view: Picker, actions: MachineActions): HTMLElement[] {
  const parts = [el("h4", "machine-title", view.title)];
  if (!view.available) return [...parts, el("p", "supporting", view.note)];
  const button = el("button", "picker-button", "Choose", { type: "button" });
  button.addEventListener("click", () => actions.openPicker(view.source));
  return [...parts, button];
}
