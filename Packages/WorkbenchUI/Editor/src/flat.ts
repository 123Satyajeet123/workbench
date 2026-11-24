import { formatLine, parseLine, type Line, type LineKind, type Run, type Style } from "./codec.ts";
import type { Change, PageBlock } from "./bridge.generated.ts";
import type { FlatBlock } from "./diff.ts";

/** A block as the editor holds it, or as the editor takes it: plain data, no editor types, so it can be tested alone. */
export interface EditorBlock {
  id: string;
  type: string;
  props: Record<string, unknown>;
  content?: InlineContent[] | undefined;
  children: EditorBlock[];
}

export type InlineContent =
  | { type: "text"; text: string; styles: Partial<Record<Style, true>> }
  | { type: "link"; href: string; content: { type: "text"; text: string; styles: Partial<Record<Style, true>> }[] };

export const MACHINE = "machine";

const TYPE_OF_KIND: Record<LineKind, string> = {
  paragraph: "paragraph",
  heading: "heading",
  bullet: "bulletListItem",
  numbered: "numberedListItem",
  check: "checkListItem",
  toggle: "toggleListItem",
  quote: "quote",
  callout: "callout",
  divider: "divider",
};
const KIND_OF_TYPE = Object.fromEntries(Object.entries(TYPE_OF_KIND).map(([kind, type]) => [type, kind])) as Record<string, LineKind>;
const STYLES: Style[] = ["bold", "italic", "strike", "code"];

export function runsOf(content: InlineContent[] | undefined): Run[] {
  const runs: Run[] = [];
  for (const piece of content ?? []) {
    const parts = piece.type === "link" ? piece.content.map((part) => ({ part, href: piece.href })) : [{ part: piece, href: undefined }];
    for (const { part, href } of parts) {
      if (part.text === "") continue;
      const run: Run = { text: part.text, styles: STYLES.filter((style) => part.styles[style]) };
      if (href !== undefined) run.href = href;
      runs.push(run);
    }
  }
  return runs;
}

export function contentOf(runs: Run[]): InlineContent[] {
  const content: InlineContent[] = [];
  for (const run of runs) {
    const text = { type: "text" as const, text: run.text, styles: Object.fromEntries(run.styles.map((style) => [style, true])) };
    const last = content[content.length - 1];
    if (run.href === undefined) content.push(text);
    else if (last?.type === "link" && last.href === run.href) last.content.push(text);
    else content.push({ type: "link", href: run.href, content: [text] });
  }
  return content;
}

export function lineOf(block: EditorBlock, depth: number): Line {
  const kind = KIND_OF_TYPE[block.type] ?? "paragraph";
  return {
    kind,
    depth,
    level: Number(block.props["level"] ?? 1),
    checked: block.props["checked"] === true,
    runs: runsOf(block.content),
  };
}

/** The page in reading order, nested blocks after their parent. A paragraph's text is the line Swift stores. */
export function flatten(blocks: EditorBlock[], depth = 0): FlatBlock[] {
  return blocks.flatMap((block) => [
    block.type === MACHINE
      ? { id: block.id, kind: "machine" as const, text: "" }
      : { id: block.id, kind: "note" as const, text: formatLine(lineOf(block, depth)) },
    ...flatten(block.children, depth + 1),
  ]);
}

export function blockOf(page: PageBlock): { block: EditorBlock; depth: number } {
  if (page.kind === "machine") {
    return { block: { id: page.id, type: MACHINE, props: { view: JSON.stringify(page.view) }, children: [] }, depth: 0 };
  }
  const line = parseLine(page.text);
  const props: Record<string, unknown> = {};
  if (line.kind === "heading") props["level"] = line.level;
  if (line.kind === "check") props["checked"] = line.checked;
  const block: EditorBlock = { id: page.id, type: TYPE_OF_KIND[line.kind], props, children: [] };
  if (line.kind !== "divider") block.content = contentOf(line.runs);
  return { block, depth: line.depth };
}

/**
 * The blocks of the page as a tree. A block nests under the block above it that is one level up. A machine block and
 * a divider hold nothing, and a block that would nest under one stays beside it.
 */
export function treeOf(page: PageBlock[]): EditorBlock[] {
  const roots: EditorBlock[] = [];
  const open: { block: EditorBlock; depth: number }[] = [];
  for (const item of page) {
    const { block, depth } = blockOf(item);
    while (open.length > 0 && open[open.length - 1]!.depth >= Math.min(depth, open.length)) open.pop();
    const parent = open[open.length - 1];
    const holds = parent !== undefined && parent.block.type !== MACHINE && parent.block.type !== "divider";
    if (parent && holds && depth > parent.depth) parent.block.children.push(block);
    else roots.push(block);
    open.push({ block, depth: parent && holds && depth > parent.depth ? parent.depth + 1 : 0 });
  }
  return roots;
}

/** The page `flat` after Swift made `change`, as Swift means it: the block stands right after the one it names. */
export function applyToFlat(flat: FlatBlock[], change: Change): FlatBlock[] {
  const next = flat.map((block) => ({ ...block }));
  const without = (id: string) => {
    const at = next.findIndex((block) => block.id === id);
    return at < 0 ? undefined : next.splice(at, 1)[0];
  };
  const place = (after: string | null, block: FlatBlock) => {
    const at = after === null ? -1 : next.findIndex((candidate) => candidate.id === after);
    next.splice(at + 1, 0, block);
  };
  switch (change.change) {
    case "insert":
      place(change.after, flatOf(change.block));
      break;
    case "update": {
      const at = next.findIndex((block) => block.id === change.block.id);
      if (at >= 0) next[at] = flatOf(change.block);
      break;
    }
    case "remove":
      without(change.id);
      break;
    case "move": {
      const moved = without(change.id);
      if (moved) place(change.after, moved);
      break;
    }
  }
  return next;
}

function flatOf(page: PageBlock): FlatBlock {
  if (page.kind === "machine") return { id: page.id, kind: "machine", text: "" };
  const { block, depth } = blockOf(page);
  return { id: page.id, kind: "note", text: formatLine(lineOf(block, depth)) };
}
