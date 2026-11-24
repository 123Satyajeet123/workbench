import assert from "node:assert/strict";
import { test } from "node:test";
import { diff, type FlatBlock } from "../src/diff.ts";

const note = (id: string, text: string): FlatBlock => ({ id, kind: "note", text });
const machine = (id: string): FlatBlock => ({ id, kind: "machine", text: "" });

test("no change gives no ops", () => {
  const page = [note("a", "one"), machine("m"), note("b", "two")];
  assert.deepEqual(diff(page, page.map((block) => ({ ...block }))), []);
});

test("typing is one update", () => {
  assert.deepEqual(diff([note("a", "one")], [note("a", "one!")]), [{ op: "update", id: "a", text: "one!" }]);
});

test("a new paragraph is an insert after its neighbour", () => {
  const ops = diff([note("a", "one"), machine("m")], [note("a", "one"), note("n", "new"), machine("m")]);
  assert.deepEqual(ops, [{ op: "insert", id: "n", after: "a", text: "new" }]);
});

test("a new first paragraph goes after nothing", () => {
  assert.deepEqual(diff([note("a", "x")], [note("n", "y"), note("a", "x")]), [{ op: "insert", id: "n", after: null, text: "y" }]);
});

test("a removed paragraph is a delete, a removed blank one is nothing", () => {
  assert.deepEqual(diff([note("a", "one"), note("b", "two")], [note("b", "two")]), [{ op: "delete", id: "a" }]);
  assert.deepEqual(diff([note("a", "one"), note("b", "")], [note("a", "one")]), []);
});

test("Backspace at the start joins the paragraph into the one before it", () => {
  const ops = diff([note("a", "Hello "), note("b", "world")], [note("a", "Hello world")]);
  assert.deepEqual(ops, [
    { op: "merge", id: "b", into: "a" },
    { op: "update", id: "a", text: "Hello world" },
  ]);
});

test("removing the words of a paragraph is a delete even when the one before changes", () => {
  const ops = diff([note("a", "Hello"), note("b", "world")], [note("a", "Hello there")]);
  assert.deepEqual(ops, [{ op: "delete", id: "b" }, { op: "update", id: "a", text: "Hello there" }]);
});

test("one block moved down is one move, also past a machine block", () => {
  const ops = diff([note("a", "1"), machine("m"), note("b", "2")], [machine("m"), note("b", "2"), note("a", "1")]);
  assert.deepEqual(ops, [{ op: "move", id: "a", after: "b" }]);
});

test("a machine block removed is a delete", () => {
  assert.deepEqual(diff([machine("m")], []), [{ op: "delete", id: "m" }]);
});

test("applying the ops gives the page", () => {
  const before = [note("a", "1"), note("b", "2"), machine("m"), note("c", "3"), note("d", "4")];
  const after = [note("d", "4!"), note("n", "x"), note("a", "1"), machine("m"), note("c", "3")];
  const page = before.map((block) => ({ ...block }));
  for (const op of diff(before, after)) {
    if (op.op === "delete" || op.op === "merge") page.splice(page.findIndex((b) => b.id === op.id), 1);
    else if (op.op === "update") page.find((b) => b.id === op.id)!.text = op.text;
    else if (op.op === "insert" || op.op === "move") {
      const block = op.op === "move" ? page.splice(page.findIndex((b) => b.id === op.id), 1)[0]! : note(op.id, op.text);
      page.splice(op.after === null ? 0 : page.findIndex((b) => b.id === op.after) + 1, 0, block);
    }
  }
  assert.deepEqual(page, after);
});
