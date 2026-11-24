import type { Block, BlockNoteEditor } from "@blocknote/core";
import { SideMenuExtension } from "@blocknote/core/extensions";
import { el } from "../dom.ts";
import { MACHINE } from "../flat.ts";
import { floatingPanel, placeBelow } from "./popup.ts";

const TURN_INTO: { title: string; block: { type: string; props?: Record<string, unknown> } }[] = [
  { title: "Text", block: { type: "paragraph" } },
  { title: "Heading 1", block: { type: "heading", props: { level: 1 } } },
  { title: "Heading 2", block: { type: "heading", props: { level: 2 } } },
  { title: "Heading 3", block: { type: "heading", props: { level: 3 } } },
  { title: "Bulleted list", block: { type: "bulletListItem" } },
  { title: "Numbered list", block: { type: "numberedListItem" } },
  { title: "To-do list", block: { type: "checkListItem" } },
  { title: "Toggle list", block: { type: "toggleListItem" } },
  { title: "Quote", block: { type: "quote" } },
  { title: "Callout", block: { type: "callout" } },
];

type AnyEditor = BlockNoteEditor<any, any, any>;
type AnyBlock = Block<any, any, any>;

function withoutIds(block: AnyBlock): Record<string, unknown> {
  const { id: _id, children, ...rest } = block;
  return { ...rest, children: children.map(withoutIds) };
}

/** The handle that shows beside the hovered block, and the menu it opens: turn into, duplicate, delete. */
export function mountBlockMenu(editor: AnyEditor): void {
  const side = editor.getExtension(SideMenuExtension);
  if (!side) return;
  const bar = el("div", "side-menu");
  bar.hidden = true;
  const add = el("button", "side-button", "+", { type: "button", "aria-label": "Add a block below" });
  const handle = el("button", "side-button side-handle", "⋮⋮", { type: "button", draggable: "true", "aria-label": "Drag this block, or open its menu" });
  bar.append(add, handle);
  document.body.append(bar);
  side.setMenuElement(bar);
  const panel = floatingPanel("block-menu");
  let current: AnyBlock | undefined;

  const closePanel = () => {
    panel.hidden = true;
    side.unfreezeMenu();
  };

  const row = (title: string, run: () => void) => {
    const button = el("button", "menu-row", undefined, { type: "button" });
    button.append(el("span", "menu-title", title));
    button.addEventListener("click", () => {
      closePanel();
      run();
    });
    return button;
  };

  const openPanel = () => {
    if (!current) return;
    const block = current;
    side.freezeMenu();
    panel.replaceChildren();
    if (block.type === MACHINE) {
      panel.append(row("Remove from page", () => editor.removeBlocks([block])));
    } else {
      panel.append(el("div", "menu-heading", "Turn into"));
      for (const choice of TURN_INTO) panel.append(row(choice.title, () => editor.updateBlock(block, choice.block as never)));
      panel.append(el("div", "menu-rule"));
      panel.append(row("Duplicate", () => editor.insertBlocks([withoutIds(block) as never], block, "after")));
      panel.append(row("Delete", () => editor.removeBlocks([block])));
    }
    placeBelow(panel, handle.getBoundingClientRect());
  };

  side.store.subscribe(() => {
    const state = side.store.state;
    if (!state || !state.show) {
      if (panel.hidden) bar.hidden = true;
      return;
    }
    current = state.block as AnyBlock;
    bar.hidden = false;
    bar.style.top = `${state.referencePos.top}px`;
    bar.style.left = `${state.referencePos.left - bar.offsetWidth - 4}px`;
  });

  handle.addEventListener("click", () => (panel.hidden ? openPanel() : closePanel()));
  handle.addEventListener("dragstart", (event) => current && side.blockDragStart(event, current));
  handle.addEventListener("dragend", () => side.blockDragEnd());
  add.addEventListener("click", () => {
    if (!current) return;
    const [created] = editor.insertBlocks([{ type: "paragraph" } as never], current, "after");
    if (created) editor.setTextCursorPosition(created, "end");
    editor.focus();
  });
  document.addEventListener("mousedown", (event) => {
    if (!panel.hidden && !panel.contains(event.target as Node) && event.target !== handle) closePanel();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !panel.hidden) closePanel();
  });
}
