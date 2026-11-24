export type Style = "bold" | "italic" | "strike" | "code";

export interface Run {
  text: string;
  styles: Style[];
  href?: string;
}

export type LineKind = "paragraph" | "heading" | "bullet" | "numbered" | "check" | "toggle" | "quote" | "callout" | "divider";

/** One stored line of the person: what kind of block it is, how deep it nests, and its words with their marks. */
export interface Line {
  kind: LineKind;
  depth: number;
  level: number;
  checked: boolean;
  runs: Run[];
}

const STYLE_ORDER: Style[] = ["bold", "italic", "strike", "code"];
const DELIMITER: Record<Style, string> = { bold: "*", italic: "_", strike: "~", code: "`" };
const STYLE_OF: Record<string, Style> = { "*": "bold", _: "italic", "~": "strike", "`": "code" };
const SPECIAL = new Set(["\\", "*", "_", "~", "`", "[", "]"]);
const INDENT = "  ";

const PREFIXES: { kind: LineKind; prefix: string; pattern: RegExp; level?: number; checked?: boolean }[] = [
  { kind: "heading", prefix: "### ", pattern: /^### /, level: 3 },
  { kind: "heading", prefix: "## ", pattern: /^## /, level: 2 },
  { kind: "heading", prefix: "# ", pattern: /^# /, level: 1 },
  { kind: "check", prefix: "- [x] ", pattern: /^- \[x\] /, checked: true },
  { kind: "check", prefix: "- [ ] ", pattern: /^- \[ \] /, checked: false },
  { kind: "bullet", prefix: "- ", pattern: /^- / },
  { kind: "numbered", prefix: "1. ", pattern: /^\d+\. / },
  { kind: "toggle", prefix: "+ ", pattern: /^\+ / },
  { kind: "callout", prefix: "> [!note] ", pattern: /^> \[!note\] / },
  { kind: "quote", prefix: "> ", pattern: /^> / },
];

const DIVIDER = "---";
const LOOKS_LIKE_A_PREFIX = /^(#{1,3} |[-+>] |\d+\. |---$| )/;

export function emptyLine(): Line {
  return { kind: "paragraph", depth: 0, level: 1, checked: false, runs: [] };
}

export function parseLine(text: string): Line {
  const depth = indentation(text);
  let rest = text.slice(depth * INDENT.length);
  const line: Line = { ...emptyLine(), depth };
  if (rest === DIVIDER) return { ...line, kind: "divider" };
  const prefix = PREFIXES.find((candidate) => candidate.pattern.test(rest));
  if (prefix) {
    rest = rest.replace(prefix.pattern, "");
    line.kind = prefix.kind;
    line.level = prefix.level ?? 1;
    line.checked = prefix.checked ?? false;
  }
  line.runs = parseInline(rest);
  return line;
}

export function formatLine(line: Line): string {
  const indent = INDENT.repeat(line.depth);
  if (line.kind === "divider") return indent + DIVIDER;
  const words = formatInline(line.runs);
  if (line.kind === "paragraph") return indent + (LOOKS_LIKE_A_PREFIX.test(words) ? "\\" + words : words);
  const prefix = PREFIXES.find(
    (candidate) =>
      candidate.kind === line.kind &&
      (candidate.level ?? 1) === (line.kind === "heading" ? line.level : 1) &&
      (candidate.checked ?? false) === (line.kind === "check" ? line.checked : false),
  );
  if (!prefix) throw new Error(`no prefix for ${line.kind}`);
  const first = words.startsWith(" ") ? "\\" + words : words;
  return indent + (line.kind === "numbered" ? "1. " : prefix.prefix) + first;
}

/** Whether a stored line has words to keep. A divider has none and is kept. */
export function hasWords(text: string): boolean {
  const line = parseLine(text);
  return line.kind === "divider" || line.runs.some((run) => run.text.trim() !== "");
}

function indentation(text: string): number {
  let spaces = 0;
  while (text.startsWith(INDENT, spaces * INDENT.length)) spaces += 1;
  return spaces;
}

export function formatInline(runs: Run[]): string {
  let out = "";
  let index = 0;
  while (index < runs.length) {
    const run = runs[index]!;
    if (run.href !== undefined) {
      const end = extent(runs, index, (candidate) => candidate.href === run.href);
      out += `[${formatInline(runs.slice(index, end).map(dropHref))}](${escape(run.href, "()")})`;
      index = end;
      continue;
    }
    const style = STYLE_ORDER.find((candidate) => run.styles.includes(candidate));
    if (style === undefined) {
      out += escape(run.text);
      index += 1;
      continue;
    }
    const end = extent(runs, index, (candidate) => candidate.href === undefined && candidate.styles.includes(style));
    const inner = runs.slice(index, end).map((member) => ({ ...member, styles: member.styles.filter((s) => s !== style) }));
    out += DELIMITER[style] + formatInline(inner) + DELIMITER[style];
    index = end;
  }
  return out;
}

function dropHref(run: Run): Run {
  const { href: _href, ...rest } = run;
  return rest;
}

function extent(runs: Run[], from: number, has: (run: Run) => boolean): number {
  let end = from;
  while (end < runs.length && has(runs[end]!)) end += 1;
  return end;
}

function escape(text: string, extra = ""): string {
  let out = "";
  for (const char of text) {
    if (char === "\n") out += "\\n";
    else if (SPECIAL.has(char) || extra.includes(char)) out += "\\" + char;
    else out += char;
  }
  return out;
}

export function parseInline(text: string): Run[] {
  const parser = new InlineParser(text);
  return parser.parse();
}

class InlineParser {
  private index = 0;
  private runs: Run[] = [];
  private readonly literalDelimiters: Set<number>;
  private readonly text: string;
  private readonly styles: Set<Style>;

  constructor(text: string, styles = new Set<Style>()) {
    this.text = text;
    this.styles = styles;
    this.literalDelimiters = unmatchedDelimiters(text);
  }

  parse(): Run[] {
    let word = "";
    const flush = (href?: string) => {
      if (word !== "") this.push(word, href);
      word = "";
    };
    while (this.index < this.text.length) {
      const char = this.text[this.index]!;
      if (char === "\\") {
        word += this.escaped();
      } else if (char in STYLE_OF && !this.literalDelimiters.has(this.index)) {
        flush();
        const style = STYLE_OF[char]!;
        if (this.styles.has(style)) this.styles.delete(style);
        else this.styles.add(style);
        this.index += 1;
      } else if (char === "[") {
        const link = this.link();
        if (link) {
          flush();
          for (const run of new InlineParser(link.label, new Set(this.styles)).parse()) this.push(run.text, link.url, run.styles);
        } else {
          word += char;
          this.index += 1;
        }
      } else {
        word += char;
        this.index += 1;
      }
    }
    flush();
    return this.runs;
  }

  private escaped(): string {
    const next = this.text[this.index + 1];
    if (next === undefined) {
      this.index += 1;
      return "\\";
    }
    this.index += 2;
    return next === "n" ? "\n" : next;
  }

  private link(): { label: string; url: string } | undefined {
    const close = findUnescaped(this.text, "]", this.index + 1);
    if (close < 0 || this.text[close + 1] !== "(") return undefined;
    const end = findUnescaped(this.text, ")", close + 2);
    if (end < 0) return undefined;
    const label = this.text.slice(this.index + 1, close);
    const url = unescape(this.text.slice(close + 2, end));
    this.index = end + 1;
    return { label, url };
  }

  private push(text: string, href?: string, extra?: Style[]) {
    const styles = STYLE_ORDER.filter((style) => this.styles.has(style) || extra?.includes(style));
    const last = this.runs[this.runs.length - 1];
    if (last && last.href === href && sameStyles(last.styles, styles)) {
      last.text += text;
      return;
    }
    this.runs.push(href === undefined ? { text, styles } : { text, styles, href });
  }
}

function sameStyles(a: Style[], b: Style[]): boolean {
  return a.length === b.length && a.every((style, index) => style === b[index]);
}

function findUnescaped(text: string, target: string, from: number): number {
  for (let index = from; index < text.length; index += 1) {
    if (text[index] === "\\") index += 1;
    else if (text[index] === target) return index;
  }
  return -1;
}

function unescape(text: string): string {
  return text.replace(/\\(.)/gs, (_all, char: string) => char);
}

/** The delimiters with no partner: they stay words. A style needs an even number of delimiters outside links' URLs. */
function unmatchedDelimiters(text: string): Set<number> {
  const seen: Record<string, number[]> = {};
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;
    if (char === "\\") index += 1;
    else if (char in STYLE_OF) (seen[char] ??= []).push(index);
  }
  const unmatched = new Set<number>();
  for (const positions of Object.values(seen)) if (positions.length % 2 === 1) unmatched.add(positions[positions.length - 1]!);
  return unmatched;
}
