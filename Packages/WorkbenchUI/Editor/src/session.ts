import { BlockNoteEditor, getNodeById, type PartialBlock } from "@blocknote/core";
import type { Ack, Apply, Change, Load, Op } from "./bridge.generated.ts";
import { listen, reportBlockedLoads, send } from "./bridge.ts";
import { applyEnvironment } from "./environment.ts";
import { applyToFlat, blockOf, FIELD, flatten, MACHINE, plainText, treeOf, type EditorBlock } from "./flat.ts";
import { diff, type FlatBlock } from "./diff.ts";
import type { MachineActions } from "./machine.ts";
import { registerHint } from "./hint.ts";
import { reportLayout } from "./layout.ts";
import { createSchema } from "./schema.ts";
import { mountBlockMenu } from "./ui/blockMenu.ts";
import { mountFormattingToolbar } from "./ui/formattingToolbar.ts";
import { mountSlashMenu } from "./ui/slashMenu.ts";

const QUIET = 250;
const ASK = /^\/ask\s+(\S.*)$/;

declare global {
  interface Window {
    wbEditor: BlockNoteEditor<any, any, any>;
  }
}

/** The editor holds the committed page and the person's typing. It tells Swift what the person did, and shows what Swift committed. */
export function start(host: HTMLElement): void {
  const marks: Op[] = [];
  const actions: MachineActions = {
    openCite: (ref) => send({ type: "open", target: { kind: "cite", ref } }),
    act: (name) => send({ type: "open", target: { kind: "action", name } }),
    openPicker: (source) => send({ type: "open", target: { kind: "picker", source } }),
    mark: (fact, mark) => {
      marks.push({ op: "mark", fact, mark });
      flush();
    },
    retitle: (id, text) => {
      marks.push({ op: "heading", id, text });
      flush();
    },
    setting: (key, value) => {
      marks.push({ op: "setting", key, value });
      flush();
    },
    changeView: (id, form, groupBy) => {
      marks.push({ op: "view", id, form, groupBy });
      flush();
    },
  };
  const editor: BlockNoteEditor<any, any, any> = BlockNoteEditor.create({
    schema: createSchema(actions),
    animations: false,
    _tiptapOptions: { injectCSS: false },
  });
  editor.unregisterExtension("placeholder");
  registerHint(editor);
  window.wbEditor = editor;
  editor.mount(host);

  let committed: FlatBlock[] = [];
  let seq = 0;
  let waiting = false;
  let composing = false;
  let flushRequested = false;
  /** The words of a field are sent when the person leaves it or presses Return, never while they type. */
  let leavingField = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  const blocks = () => editor.document as unknown as EditorBlock[];
  const snapshot = () => flatten(blocks());

  /** The words of the person end in a paragraph, before any field that closes the page, so there is a line to write on. */
  function keepAParagraphAtTheEnd(): void {
    const last = editor.document.findLast((block) => !block.id.startsWith("document."));
    if (!last || last.type !== MACHINE) return;
    editor.transact((tr) => {
      tr.setMeta("addToHistory", false);
      editor.insertBlocks([{ type: "paragraph" }], last, "after");
    });
  }

  function schedule(delay = QUIET): void {
    clearTimeout(timer);
    timer = setTimeout(flush, delay);
  }

  function dropForeignMachineBlocks(): void {
    const known = new Set(committed.filter((block) => block.kind !== "note").map((block) => block.id));
    const foreign = snapshot().filter((block) => block.kind !== "note" && !known.has(block.id));
    if (foreign.length > 0) editor.removeBlocks(foreign.map((block) => block.id));
  }

  function withoutUnfinishedField(page: FlatBlock[]): FlatBlock[] {
    const leaving = leavingField || flushRequested;
    leavingField = false;
    const here = leaving ? undefined : editor.getTextCursorPosition().block;
    if (here?.type !== FIELD) return page;
    const old = committed.find((block) => block.id === here.id);
    return page.map((block) => (block.id === here.id && old ? old : block));
  }

  function flush(): void {
    if (waiting || composing) return;
    dropForeignMachineBlocks();
    const now = withoutUnfinishedField(snapshot());
    const ops = [...diff(committed, now), ...marks.splice(0)];
    if (ops.length === 0) {
      if (flushRequested) send({ type: "idle" });
      flushRequested = false;
      return;
    }
    committed = now;
    waiting = true;
    seq += 1;
    send({ type: "ops", seq, ops: ops as [Op, ...Op[]] });
  }

  function load(message: Load): void {
    const tree = treeOf(message.blocks) as unknown as PartialBlock<any, any, any>[];
    editor.transact((tr) => {
      tr.setMeta("addToHistory", false);
      editor.replaceBlocks(editor.document, tree.length > 0 ? tree : [{ type: "paragraph" }]);
    });
    keepAParagraphAtTheEnd();
    committed = snapshot();
  }

  function insert(change: Extract<Change, { change: "insert" }>): void {
    const { block } = blockOf(change.block);
    const partial = block as unknown as PartialBlock<any, any, any>;
    if (change.after === null) {
      editor.insertBlocks([partial], editor.document[0]!, "before");
      return;
    }
    let anchor = editor.getBlock(change.after);
    for (let parent = anchor && editor.getParentBlock(anchor); parent; parent = editor.getParentBlock(parent)) anchor = parent;
    if (anchor) editor.insertBlocks([partial], anchor, "after");
  }

  function applyChange(change: Change): void {
    switch (change.change) {
      case "insert":
        insert(change);
        break;
      case "update": {
        const { block } = blockOf(change.block);
        const { children: _children, id: _id, ...rest } = block;
        const held = editor.getBlock(change.block.id);
        const sameWords = block.type === FIELD && held && plainText(held.content as unknown as EditorBlock["content"]) === plainText(block.content);
        const update = sameWords ? { type: rest.type, props: rest.props } : rest;
        editor.updateBlock(change.block.id, update as unknown as PartialBlock<any, any, any>);
        break;
      }
      case "remove":
        editor.removeBlocks([change.id]);
        break;
      case "move": {
        const moved = editor.getBlock(change.id);
        if (!moved) break;
        editor.removeBlocks([moved]);
        if (change.after === null) editor.insertBlocks([moved], editor.document[0]!, "before");
        else editor.insertBlocks([moved], change.after, "after");
        break;
      }
    }
    committed = applyToFlat(committed, change);
  }

  function apply(message: Apply): void {
    editor.transact((tr) => {
      tr.setMeta("addToHistory", false);
      for (const change of message.changes) applyChange(change);
    });
    keepAParagraphAtTheEnd();
  }

  function rename(from: string, to: string): void {
    editor.transact((tr) => {
      tr.setMeta("addToHistory", false);
      const found = getNodeById(from, tr.doc);
      if (found) tr.setNodeAttribute(found.posBeforeNode, "id", to);
    });
    committed = committed.map((block) => (block.id === from ? { ...block, id: to } : block));
  }

  function acknowledge(message: Ack): void {
    waiting = false;
    for (const { from, to } of message.renames) rename(from, to);
    schedule(0);
  }

  listen((message) => {
    switch (message.type) {
      case "environment":
        applyEnvironment(message, editor);
        break;
      case "load":
        load(message);
        break;
      case "apply":
        apply(message);
        break;
      case "ack":
        acknowledge(message);
        break;
      case "flush":
        clearTimeout(timer);
        flushRequested = true;
        flush();
        break;
    }
  });

  editor.onChange(() => {
    keepAParagraphAtTheEnd();
    schedule();
  });
  host.addEventListener("compositionstart", () => (composing = true), true);
  host.addEventListener("compositionend", () => {
    composing = false;
    schedule();
  }, true);
  host.addEventListener("focusout", () => {
    leavingField = true;
    schedule(0);
  });
  host.addEventListener(
    "keydown",
    (event) => {
      if (event.key !== "Enter") return;
      const here = editor.getTextCursorPosition().block;
      const request = here.type === "paragraph" ? plainText(here.content as unknown as EditorBlock["content"]).match(ASK) : null;
      if (here.type !== FIELD && !request) return;
      event.preventDefault();
      event.stopPropagation();
      if (request) {
        editor.removeBlocks([here]);
        marks.push({ op: "ask", text: request[1]!.trim() });
        flush();
        return;
      }
      leavingField = true;
      schedule(0);
    },
    true,
  );
  host.addEventListener("click", (event) => {
    const link = (event.target as Element).closest("a[href]");
    if (!link) return;
    event.preventDefault();
    send({ type: "open", target: { kind: "link", url: link.getAttribute("href") ?? "" } });
  });

  mountSlashMenu(editor);
  mountBlockMenu(editor);
  mountFormattingToolbar(editor);
  reportBlockedLoads();
  reportLayout(host);
  send({ type: "ready", contract: 1 });
}
