import type { BlockNoteEditor } from "@blocknote/core";
import { filterSuggestionItems, getDefaultSlashMenuItems, insertOrUpdateBlockForSlashMenu, SuggestionMenu } from "@blocknote/core/extensions";
import { el } from "../dom.ts";
import { floatingPanel, placeBelow } from "./popup.ts";

interface Item {
  title: string;
  subtext?: string;
  aliases?: readonly string[];
  onItemClick: () => void;
}

const KEPT = new Set(["paragraph", "heading", "heading_2", "heading_3", "numbered_list", "bullet_list", "check_list", "toggle_list", "quote", "divider"]);

function items(editor: BlockNoteEditor<any, any, any>): Item[] {
  const own = getDefaultSlashMenuItems(editor).filter((item) => KEPT.has(item.key));
  const callout: Item = {
    title: "Callout",
    subtext: "Set words apart in a note",
    aliases: ["callout", "note", "info"],
    onItemClick: () => insertOrUpdateBlockForSlashMenu(editor, { type: "callout" }),
  };
  return [...own, callout];
}

export function mountSlashMenu(editor: BlockNoteEditor<any, any, any>): void {
  const menu = editor.getExtension(SuggestionMenu);
  if (!menu) return;
  menu.addSuggestionMenu({ triggerCharacter: "/" });
  const panel = floatingPanel("slash-menu");
  let shown: Item[] = [];
  let selected = 0;

  const choose = (item: Item) => {
    menu.closeMenu();
    menu.clearQuery();
    panel.hidden = true;
    item.onItemClick();
  };

  const draw = () => {
    panel.replaceChildren();
    if (shown.length === 0) {
      panel.append(el("div", "menu-empty", "No match"));
      return;
    }
    shown.forEach((item, index) => {
      const row = el("button", index === selected ? "menu-row selected" : "menu-row", undefined, { type: "button" });
      row.append(el("span", "menu-title", item.title));
      if (item.subtext) row.append(el("span", "menu-subtext", item.subtext));
      row.addEventListener("click", () => choose(item));
      row.addEventListener("mousemove", () => {
        if (selected === index) return;
        selected = index;
        draw();
      });
      panel.append(row);
    });
    panel.querySelector(".selected")?.scrollIntoView({ block: "nearest" });
  };

  menu.store.subscribe(() => {
    const state = menu.store.state;
    if (!state || state.triggerCharacter !== "/") {
      panel.hidden = true;
      return;
    }
    shown = filterSuggestionItems(items(editor), state.query);
    selected = Math.min(selected, Math.max(0, shown.length - 1));
    if (state.query === "") selected = 0;
    draw();
    placeBelow(panel, state.referencePos);
  });

  document.addEventListener(
    "keydown",
    (event) => {
      if (panel.hidden) return;
      const step = event.key === "ArrowDown" ? 1 : event.key === "ArrowUp" ? -1 : 0;
      if (step !== 0 && shown.length > 0) {
        selected = (selected + step + shown.length) % shown.length;
        draw();
      } else if (event.key === "Enter" && shown[selected]) choose(shown[selected]!);
      else if (event.key === "Escape") menu.closeMenu();
      else return;
      event.preventDefault();
      event.stopPropagation();
    },
    true,
  );
}
