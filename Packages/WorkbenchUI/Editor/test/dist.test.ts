import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";
import { test } from "node:test";

const dist = new URL("../../Sources/WorkbenchUI/Resources/Editor/", import.meta.url);
const read = (name: string) => readFileSync(new URL(name, dist), "utf8");

test("the page loads two files and has no inline script or style", () => {
  const html = read("index.html");
  assert.deepEqual([...html.matchAll(/<script\b[^>]*>/g)].map((m) => m[0]), ['<script src="editor.js">']);
  assert.ok(!/\sstyle=|<style/i.test(html));
  assert.deepEqual([...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]).sort(), ["editor.css", "editor.js"]);
});

test("the stylesheet loads nothing", () => {
  assert.ok(!/url\(|@import|@font-face/.test(read("editor.css")));
});

test("the bundle stays small", () => {
  assert.ok(statSync(new URL("editor.js", dist)).size < 700_000);
  assert.ok(statSync(new URL("editor.css", dist)).size < 60_000);
});

test("the editor's own code has no way to reach the network", () => {
  const source = ["session", "machine", "bridge", "schema", "dom", "environment"].map((name) => readFileSync(new URL(`../src/${name}.ts`, import.meta.url), "utf8")).join("\n");
  assert.ok(!/fetch\(|XMLHttpRequest|WebSocket|innerHTML|insertAdjacentHTML|eval\(|new Function/.test(source));
});
