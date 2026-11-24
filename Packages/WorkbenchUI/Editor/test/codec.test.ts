import assert from "node:assert/strict";
import { test } from "node:test";
import { formatInline, formatLine, parseInline, parseLine, type Run, type Style } from "../src/codec.ts";

const STYLES: Style[] = ["bold", "italic", "strike", "code"];
const ALPHABET = ["a", "b", " ", "*", "_", "~", "`", "[", "]", "(", ")", "\\", "n", "#", "-", "1", ".", ">", "\n", "क", "か", "<", "&"];

function random(seed: number): () => number {
  let state = seed;
  return () => ((state = (state * 1664525 + 1013904223) >>> 0) / 2 ** 32);
}

function normalized(runs: Run[]): Run[] {
  const out: Run[] = [];
  for (const run of runs) {
    if (run.text === "") continue;
    const last = out[out.length - 1];
    const styles = STYLES.filter((style) => run.styles.includes(style));
    if (last && last.href === run.href && last.styles.join() === styles.join()) last.text += run.text;
    else out.push({ ...run, styles });
  }
  return out;
}

function randomRuns(next: () => number): Run[] {
  const count = 1 + Math.floor(next() * 5);
  return Array.from({ length: count }, () => {
    const text = Array.from({ length: 1 + Math.floor(next() * 5) }, () => ALPHABET[Math.floor(next() * ALPHABET.length)]!).join("");
    const styles = STYLES.filter(() => next() < 0.3);
    const run: Run = { text, styles };
    if (next() < 0.2) run.href = next() < 0.5 ? "https://example.com/a_b?x=(1)" : "workbench:fact/12";
    return run;
  });
}

test("inline marks round trip for random runs", () => {
  const next = random(7);
  for (let round = 0; round < 3000; round += 1) {
    const runs = normalized(randomRuns(next));
    const text = formatInline(runs);
    assert.deepEqual(parseInline(text), runs, `round ${round}: ${JSON.stringify(text)}`);
  }
});

test("every kind of line round trips for random words", () => {
  const next = random(11);
  const kinds = ["paragraph", "heading", "bullet", "numbered", "check", "toggle", "quote", "callout"] as const;
  for (let round = 0; round < 3000; round += 1) {
    const kind = kinds[Math.floor(next() * kinds.length)]!;
    const line = {
      kind,
      depth: Math.floor(next() * 3),
      level: 1 + Math.floor(next() * 3),
      checked: next() < 0.5,
      runs: normalized(randomRuns(next)),
    };
    const stored = formatLine(line);
    const back = parseLine(stored);
    assert.equal(back.kind, kind, JSON.stringify(stored));
    assert.equal(back.depth, line.depth);
    if (kind === "heading") assert.equal(back.level, line.level);
    if (kind === "check") assert.equal(back.checked, line.checked);
    assert.deepEqual(back.runs, line.runs, JSON.stringify(stored));
    assert.equal(formatLine(back), stored);
  }
});

test("a stored line is read as the person wrote it", () => {
  assert.equal(formatLine(parseLine("## Plan for *Friday*")), "## Plan for *Friday*");
  assert.deepEqual(parseLine("- [x] done").checked, true);
  assert.equal(parseLine("---").kind, "divider");
  assert.equal(parseLine("    - nested").depth, 2);
  assert.equal(formatLine(parseLine("3. third")), "1. third");
  assert.equal(parseLine("plain words").kind, "paragraph");
  assert.equal(parseLine("").runs.length, 0);
});

test("a typed marker stays words", () => {
  const stored = formatLine({ kind: "paragraph", depth: 0, level: 1, checked: false, runs: [{ text: "# not a heading", styles: [] }] });
  assert.equal(parseLine(stored).kind, "paragraph");
  assert.equal(parseLine(stored).runs[0]!.text, "# not a heading");
});

test("a mark with no partner stays words", () => {
  assert.deepEqual(parseInline("5 * 3"), [{ text: "5 * 3", styles: [] }]);
});
