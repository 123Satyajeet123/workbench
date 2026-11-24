import { send } from "./bridge.ts";

/** Tells Swift how tall the page is, and where the caret is, so the host can size the web view to the page and keep the caret in view. */
export function reportLayout(page: HTMLElement): void {
  let last = "";
  const report = () => {
    const top = page.getBoundingClientRect().top;
    const caret = caretBox(page, top);
    const height = Math.ceil(page.getBoundingClientRect().height);
    const key = `${height} ${caret?.top} ${caret?.bottom}`;
    if (key === last) return;
    last = key;
    send({ type: "layout", height, caret });
  };
  new ResizeObserver(report).observe(page);
  document.addEventListener("selectionchange", report);
}

function caretBox(page: HTMLElement, pageTop: number): { top: number; bottom: number } | null {
  const selection = document.getSelection();
  if (!selection || selection.rangeCount === 0 || !selection.isCollapsed || !page.contains(selection.anchorNode)) return null;
  const range = selection.getRangeAt(0);
  let box: DOMRect | undefined = range.getClientRects()[0];
  if (!box || (box.width === 0 && box.height === 0)) {
    const node = selection.anchorNode;
    box = (node instanceof Element ? node : node?.parentElement)?.getBoundingClientRect();
  }
  return box ? { top: Math.round(box.top - pageTop), bottom: Math.round(box.bottom - pageTop) } : null;
}
