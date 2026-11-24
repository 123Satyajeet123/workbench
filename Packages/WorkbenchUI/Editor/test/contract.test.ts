import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import Ajv2020 from "ajv/dist/2020.js";
import type { Change, Load, Ops } from "../src/bridge.generated.ts";
import { applyToFlat, flatten, treeOf } from "../src/flat.ts";
import { diff } from "../src/diff.ts";

const read = (name: string) => JSON.parse(readFileSync(new URL(`../contract/${name}`, import.meta.url), "utf8"));
const schema = read("bridge.schema.json");
const samples = read("samples.json") as { toSwift: Record<string, unknown>; toEditor: Record<string, unknown> };
const DISCRIMINATORS = ["type", "op", "change", "kind"];

function validator(direction: "ToSwift" | "ToEditor") {
  const ajv = new Ajv2020({ strict: true });
  ajv.addSchema(schema);
  return ajv.compile({ $ref: `${schema.$id}#/$defs/${direction}` });
}

test("every sample Swift writes is valid for its direction", () => {
  for (const [direction, messages] of [["ToSwift", samples.toSwift], ["ToEditor", samples.toEditor]] as const) {
    const valid = validator(direction);
    for (const [name, message] of Object.entries(messages)) {
      assert.ok(valid(message), `${name}: ${JSON.stringify(valid.errors)}`);
    }
  }
});

test("a message of the wrong shape is refused, in both directions", () => {
  const toSwift = validator("ToSwift");
  const toEditor = validator("ToEditor");
  assert.ok(!toSwift({ type: "ops", seq: 1, ops: [{ op: "explode", id: "a" }] }));
  assert.ok(!toSwift({ type: "ops", seq: 1, ops: [] }));
  assert.ok(!toSwift({ type: "ops", seq: 1, ops: [{ op: "delete", id: "a", extra: 1 }] }));
  assert.ok(!toSwift({ type: "load", blocks: [] }));
  assert.ok(!toEditor({ type: "ready", contract: 1 }));
  assert.ok(!toEditor({ type: "apply", changes: [{ change: "insert", block: { kind: "note", id: "a", text: "" } }] }));
  assert.ok(!toEditor({ type: "load", blocks: [{ kind: "machine", id: "m", view: { kind: "html", markup: "<b>" } }] }));
});

function kinds(node: unknown, found = new Set<string>(), fromSchema = false): Set<string> {
  if (Array.isArray(node)) node.forEach((item) => kinds(item, found, fromSchema));
  else if (node && typeof node === "object") {
    const object = node as Record<string, unknown>;
    for (const key of DISCRIMINATORS) {
      const property = fromSchema ? (object["properties"] as Record<string, Record<string, unknown>> | undefined)?.[key] : undefined;
      const values = fromSchema ? [property?.["const"], ...((property?.["enum"] as unknown[]) ?? [])] : [object[key]];
      for (const value of values) if (typeof value === "string") found.add(`${key}=${value}`);
    }
    Object.values(object).forEach((child) => kinds(child, found, fromSchema));
  }
  return found;
}

test("the schema and Swift's samples name the same kinds of message, op, change and block", () => {
  assert.deepEqual([...kinds(samples)].sort(), [...kinds(schema, new Set(), true)].sort());
});

test("the editor reads every page Swift sends and every change it makes", () => {
  const load = samples.toEditor["load"] as Load;
  const flat = flatten(treeOf(load.blocks) as never);
  assert.deepEqual(flat.map((block) => block.id), load.blocks.map((block) => block.id));
  const apply = samples.toEditor["apply"] as { changes: Change[] };
  const after = apply.changes.reduce(applyToFlat, flat);
  assert.deepEqual(after.map((block) => block.id), ["m9", "document.title", "n1", "m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m10"]);
});

test("the ops the editor sends are valid for Swift", () => {
  const valid = validator("ToSwift");
  const before = [{ id: "a", kind: "note" as const, text: "one" }, { id: "m", kind: "machine" as const, text: "" }];
  const after = [{ id: "n", kind: "note" as const, text: "# new" }, { id: "m", kind: "machine" as const, text: "" }, { id: "a", kind: "note" as const, text: "one two" }];
  const field = { id: "document.title", kind: "field" as const, text: "Pip" };
  const ops = diff([field, ...before], [{ ...field, text: "Pip Two" }, ...after]) as Ops["ops"];
  assert.ok(ops.some((op) => op.op === "field" && op.text === "Pip Two"));
  assert.ok(valid({ type: "ops", seq: 1, ops }), JSON.stringify(valid.errors));
});
