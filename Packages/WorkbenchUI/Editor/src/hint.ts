import type { BlockNoteEditor } from "@blocknote/core";
import { Plugin, PluginKey } from "prosemirror-state";
import { Decoration, DecorationSet } from "prosemirror-view";

const HINT = "Write, or type / for blocks";

/**
 * The words of an empty paragraph that waits for the person: the one with the caret and the last one of the page. They
 * reach the screen as a data attribute that the stylesheet shows with `::before`, so no style is added at run time.
 */
export function registerHint(editor: BlockNoteEditor<any, any, any>): void {
  editor.registerExtension({
    key: "hint",
    prosemirrorPlugins: [
      new Plugin({
        key: new PluginKey("hint"),
        props: {
          decorations(state) {
            const marks: Decoration[] = [];
            const { doc, selection } = state;
            const group = doc.firstChild;
            const last = group?.lastChild?.firstChild;
            if (group && last && last.type.name === "paragraph" && last.content.size === 0) {
              const from = 1 + group.content.size - group.lastChild!.nodeSize + 1;
              marks.push(Decoration.node(from, from + last.nodeSize, { "data-hint": HINT }));
            }
            const here = selection.$anchor;
            if (selection.empty && here.parent.type.name === "paragraph" && here.parent.content.size === 0) {
              marks.push(Decoration.node(here.before(), here.before() + here.parent.nodeSize, { "data-hint": HINT }));
            }
            return DecorationSet.create(doc, marks);
          },
        },
      }),
    ],
  });
}
