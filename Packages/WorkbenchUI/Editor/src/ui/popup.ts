import { el } from "../dom.ts";

/** A floating panel placed from a rectangle. The page is the only parent: it never leaves the editor's document. */
export function floatingPanel(className: string): HTMLElement {
  const panel = el("div", `panel ${className}`);
  panel.hidden = true;
  panel.addEventListener("mousedown", (event) => event.preventDefault());
  document.body.append(panel);
  return panel;
}

export function placeBelow(panel: HTMLElement, rect: DOMRect): void {
  panel.hidden = false;
  const gap = 6;
  const width = panel.offsetWidth;
  const height = panel.offsetHeight;
  const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8));
  const fitsBelow = rect.bottom + gap + height <= window.innerHeight;
  panel.style.left = `${left}px`;
  panel.style.top = `${fitsBelow ? rect.bottom + gap : Math.max(8, rect.top - gap - height)}px`;
}
