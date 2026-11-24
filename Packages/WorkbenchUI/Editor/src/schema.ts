import {
  BlockNoteSchema,
  createBlockSpec,
  createBulletListItemBlockSpec,
  createCheckListItemBlockSpec,
  createDividerBlockSpec,
  createHeadingBlockSpec,
  createNumberedListItemBlockSpec,
  createParagraphBlockSpec,
  createQuoteBlockSpec,
  createToggleListItemBlockSpec,
  defaultInlineContentSpecs,
  defaultStyleSpecs,
} from "@blocknote/core";
import type { MachineView } from "./bridge.generated.ts";
import { el } from "./dom.ts";
import { renderMachine, type MachineActions, type Standing } from "./machine.ts";

const callout = createBlockSpec(
  { type: "callout", propSchema: {}, content: "inline" },
  {
    render() {
      const dom = el("div", "callout");
      dom.append(el("span", "callout-mark", "i", { contenteditable: "false", "aria-hidden": "true" }));
      const contentDOM = el("div", "callout-text");
      dom.append(contentDOM);
      return { dom, contentDOM };
    },
  },
);

export const NO_VIEW: MachineView = { kind: "erased", note: "" };

export function machineSpec(actions: MachineActions) {
  return createBlockSpec(
    {
      type: "machine",
      propSchema: { view: { default: JSON.stringify(NO_VIEW) }, standing: { default: "live" } },
      content: "none",
    },
    {
      render(block) {
        const view = JSON.parse(block.props.view) as MachineView;
        return { dom: renderMachine(view, block.props.standing as Standing, block.id, actions) };
      },
    },
  );
}

export function createSchema(actions: MachineActions) {
  return BlockNoteSchema.create({
    blockSpecs: {
      paragraph: createParagraphBlockSpec(),
      heading: createHeadingBlockSpec({ levels: [1, 2, 3], allowToggleHeadings: false }),
      bulletListItem: createBulletListItemBlockSpec(),
      numberedListItem: createNumberedListItemBlockSpec(),
      checkListItem: createCheckListItemBlockSpec(),
      toggleListItem: createToggleListItemBlockSpec(),
      quote: createQuoteBlockSpec(),
      divider: createDividerBlockSpec(),
      callout: callout(),
      machine: machineSpec(actions)(),
    },
    inlineContentSpecs: {
      text: defaultInlineContentSpecs.text,
      link: defaultInlineContentSpecs.link,
    },
    styleSpecs: {
      bold: defaultStyleSpecs.bold,
      italic: defaultStyleSpecs.italic,
      strike: defaultStyleSpecs.strike,
      code: defaultStyleSpecs.code,
    },
  });
}

export type EditorSchema = ReturnType<typeof createSchema>;
