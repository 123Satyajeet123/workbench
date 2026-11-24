import type { Chip, FactRow, FactSection, GridCell, MachineView } from "./bridge.generated.ts";
import { el } from "./dom.ts";

export interface MachineActions {
  openCite(ref: string): void;
  openPicker(source: string): void;
  mark(fact: number, mark: "right" | "wrong"): void;
}

type Facts = Extract<MachineView, { kind: "facts" }>;
type Grid = Extract<MachineView, { kind: "grid" }>;
type Picker = Extract<MachineView, { kind: "picker" }>;

/** Draws a block of a machine from the data Swift worked out. It adds, counts and fetches nothing. */
export function renderMachine(view: MachineView, actions: MachineActions): HTMLElement {
  const root = el("section", `machine machine-${view.kind}`);
  root.append(...partsOf(view, actions));
  return root;
}

function partsOf(view: MachineView, actions: MachineActions): HTMLElement[] {
  switch (view.kind) {
    case "heading":
      return [el("h3", "machine-heading", view.text)];
    case "text":
      return [el("p", "machine-text", view.text), chips(view.cites, actions)];
    case "facts":
      return factsParts(view, actions);
    case "grid":
      return [el("h4", "machine-title", view.title), gridTable(view), chips(view.cites, actions)];
    case "picker":
      return pickerParts(view, actions);
    case "erased":
      return [el("p", "machine-erased", view.note)];
  }
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

function factsParts(view: Facts, actions: MachineActions): HTMLElement[] {
  const head = el("div", "machine-head");
  head.append(el("h4", "machine-title", view.title), el("span", "supporting", view.countText));
  const body = el("div", `facts facts-${view.layout}`);
  for (const section of view.sections) body.append(sectionOf(view, section, actions));
  return [head, body];
}

function sectionOf(view: Facts, section: FactSection, actions: MachineActions): HTMLElement {
  const node = el("div", "facts-section");
  if (view.layout === "counts") {
    node.append(el("span", undefined, section.name === "" ? "Facts" : section.name), el("span", "count", String(section.count)));
    return node;
  }
  if (section.name !== "") node.append(el("h5", "facts-name", section.name));
  if (view.layout === "table") node.append(factTable(view, section, actions));
  else for (const row of section.rows) node.append(factLine(row, actions));
  return node;
}

function factLine(row: FactRow, actions: MachineActions): HTMLElement {
  const line = el("div", "fact");
  const words = el("button", "fact-words", undefined, { type: "button" });
  if (row.person !== "") words.append(el("strong", undefined, row.person), document.createTextNode(" "));
  words.append(document.createTextNode(row.words));
  words.addEventListener("click", () => actions.openCite(`fact:${row.fact}`));
  line.append(words, markButtons(row, actions));
  return line;
}

function factTable(view: Facts, section: FactSection, actions: MachineActions): HTMLElement {
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
  return table;
}

function markButtons(row: FactRow, actions: MachineActions): HTMLElement {
  const marks = el("span", "marks");
  for (const [mark, label] of [["right", "Right"], ["wrong", "Wrong"]] as const) {
    const button = el("button", `mark mark-${mark}`, label, { type: "button", "aria-label": `Mark this fact ${mark}` });
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
