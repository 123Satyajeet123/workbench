import type { Environment } from "./bridge.generated.ts";

export function applyEnvironment(environment: Environment, editor: { isEditable: boolean }): void {
  editor.isEditable = environment.editable;
  const root = document.documentElement;
  root.dataset["theme"] = environment.appearance;
  root.dataset["motion"] = environment.reduceMotion ? "reduce" : "full";
  for (const [name, value] of Object.entries(environment.tokens)) root.style.setProperty(`--wb-${name}`, value);
}
