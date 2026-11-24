import { build } from "esbuild";
import { compileFromFile } from "json-schema-to-typescript";
import { copyFile, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";

const out = new URL("../Sources/WorkbenchUI/Resources/Editor/", import.meta.url);
const root = new URL("./", import.meta.url);

const types = await compileFromFile(new URL("contract/bridge.schema.json", root).pathname, {
  unreachableDefinitions: true,
  additionalProperties: false,
  bannerComment: "/* Generated from contract/bridge.schema.json by build.mjs. Do not edit. */",
});
await writeFile(new URL("src/bridge.generated.ts", root), types);

await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
await build({
  entryPoints: [new URL("src/main.ts", root).pathname],
  bundle: true,
  minify: true,
  format: "iife",
  target: "safari17",
  legalComments: "none",
  define: { "process.env.NODE_ENV": '"production"' },
  outfile: new URL("editor.js", out).pathname,
});
await build({
  entryPoints: [new URL("src/editor.css", root).pathname],
  bundle: true,
  minify: true,
  outfile: new URL("editor.css", out).pathname,
});
await copyFile(new URL("src/index.html", root), new URL("index.html", out));

for (const name of ["index.html", "editor.js", "editor.css"]) {
  const bytes = await readFile(new URL(name, out));
  console.log(`${name}: ${bytes.length} bytes, ${gzipSync(bytes).length} gzipped`);
}
