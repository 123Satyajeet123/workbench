import type { BlockNoteEditor } from "@blocknote/core";
import { el } from "../dom.ts";
import { floatingPanel, placeBelow } from "./popup.ts";

const ALLOWED_LINK = /^(https?:|mailto:)/i;

const BUTTONS = [
  { style: "bold", label: "B", title: "Bold" },
  { style: "italic", label: "I", title: "Italic" },
  { style: "strike", label: "S", title: "Strikethrough" },
  { style: "code", label: "</>", title: "Code" },
] as const;

/** A small bar over selected words: bold, italic, strikethrough, code, link. */
export function mountFormattingToolbar(editor: BlockNoteEditor<any, any, any>): void {
  const panel = floatingPanel("format-bar");
  const buttons = BUTTONS.map(({ style, label, title }) => {
    const button = el("button", `format-button format-${style}`, label, { type: "button", title, "aria-label": title });
    button.addEventListener("click", () => editor.toggleStyles({ [style]: true } as never));
    return { style, button };
  });
  const link = el("button", "format-button", "Link", { type: "button", title: "Add a link" });
  const address = el("input", "format-input", undefined, { type: "text", placeholder: "Paste a link and press Return", "aria-label": "Link address" });
  address.hidden = true;
  address.addEventListener("keydown", (event) => {
    event.stopPropagation();
    if (event.key !== "Enter") return;
    event.preventDefault();
    if (ALLOWED_LINK.test(address.value)) editor.createLink(address.value);
    address.value = "";
    address.hidden = true;
    editor.focus();
  });
  link.addEventListener("click", () => {
    address.hidden = false;
    address.focus();
  });
  panel.addEventListener("mousedown", (event) => {
    if (event.target !== address) event.preventDefault();
  });
  panel.append(...buttons.map(({ button }) => button), link, address);

  editor.onSelectionChange(() => {
    const selection = editor.prosemirrorState.selection;
    const rect = editor.getSelectionBoundingBox();
    const showing = !selection.empty && editor.isFocused() && rect !== undefined && editor.getSelectedText() !== "";
    if (!showing) {
      if (document.activeElement !== address) panel.hidden = true;
      return;
    }
    const active = editor.getActiveStyles() as Record<string, unknown>;
    for (const { style, button } of buttons) button.classList.toggle("active", active[style] === true);
    placeBelow(panel, rect);
  });
}
