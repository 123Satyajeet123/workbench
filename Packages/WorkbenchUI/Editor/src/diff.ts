import type { Op } from "./bridge.generated.ts";
import { formatInline, hasWords, parseLine } from "./codec.ts";

/** One block of the page in reading order, nested blocks included. A paragraph of the person has its stored line. */
export interface FlatBlock {
  id: string;
  kind: "note" | "machine";
  text: string;
}

/** The ops that turn the page `before` into the page `after`, in an order Swift can apply one by one. */
export function diff(wasPage: FlatBlock[], isPage: FlatBlock[]): Op[] {
  const before = wasPage.filter(isStored);
  const after = isPage.filter(isStored);
  const was = new Map(before.map((block) => [block.id, block]));
  const is = new Map(after.map((block) => [block.id, block]));
  const ops: Op[] = [];
  before.forEach((block, index) => {
    if (is.has(block.id)) return;
    const into = joinedInto(block, before[index - 1], is);
    if (into) {
      ops.push({ op: "merge", id: block.id, into });
    } else {
      ops.push({ op: "delete", id: block.id });
    }
  });
  const stable = unmoved(before, after, was);
  let previous: string | null = null;
  for (const block of after) {
    const old = was.get(block.id);
    if (!old) ops.push({ op: "insert", id: block.id, after: previous, text: block.kind === "note" ? block.text : "" });
    else if (!stable.has(block.id)) ops.push({ op: "move", id: block.id, after: previous });
    if (old && block.kind === "note" && old.text !== block.text) ops.push({ op: "update", id: block.id, text: block.text });
    previous = block.id;
  }
  return ops;
}

/** A paragraph with no words is not stored: it is not on the page until the person writes in it. */
function isStored(block: FlatBlock): boolean {
  return block.kind === "machine" || hasWords(block.text);
}

/** The paragraph a removed paragraph was joined to: the one before it, whose words now end with the removed words. */
function joinedInto(removed: FlatBlock, before: FlatBlock | undefined, is: Map<string, FlatBlock>): string | undefined {
  if (removed.kind !== "note" || !before || before.kind !== "note") return undefined;
  const now = is.get(before.id);
  if (!now || now.kind !== "note") return undefined;
  const words = (text: string) => formatInline(parseLine(text).runs);
  return words(now.text) === words(before.text) + words(removed.text) ? before.id : undefined;
}

/** The blocks that kept their relative order: the longest increasing run of their old positions. */
function unmoved(before: FlatBlock[], after: FlatBlock[], was: Map<string, FlatBlock>): Set<string> {
  const oldIndex = new Map(before.map((block, index) => [block.id, index]));
  const common = after.filter((block) => was.has(block.id));
  const positions = common.map((block) => oldIndex.get(block.id)!);
  const tails: number[] = [];
  const links: number[] = new Array(positions.length).fill(-1);
  const tailAt: number[] = [];
  positions.forEach((position, index) => {
    let low = 0;
    let high = tails.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (tails[middle]! < position) low = middle + 1;
      else high = middle;
    }
    tails[low] = position;
    tailAt[low] = index;
    links[index] = low > 0 ? tailAt[low - 1]! : -1;
  });
  const keep = new Set<string>();
  for (let at = tails.length ? tailAt[tails.length - 1]! : -1; at >= 0; at = links[at]!) keep.add(common[at]!.id);
  return keep;
}
