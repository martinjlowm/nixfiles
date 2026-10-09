// Finds the comment blocks a diff adds and turns Jev's answers about each one
// into the actions the comment-audit skill reasons about. Pure functions only,
// so comments.test.ts covers everything but the network.

export type CommentSyntax = { line: string[]; block?: [string, string]; quotes: string };

const SLASH: CommentSyntax = { line: ['//'], block: ['/*', '*/'], quotes: `"'\`` };
// A Rust `'` opens a lifetime or a char, so only double quotes delimit strings.
const RUST: CommentSyntax = { line: ['//'], block: ['/*', '*/'], quotes: '"' };
const HASH: CommentSyntax = { line: ['#'], quotes: `"'` };
const DASH: CommentSyntax = { line: ['--'], quotes: `'"` };

const SYNTAX_BY_EXTENSION: Record<string, CommentSyntax> = {
  rs: RUST,
  ts: SLASH,
  tsx: SLASH,
  mts: SLASH,
  cts: SLASH,
  js: SLASH,
  jsx: SLASH,
  mjs: SLASH,
  cjs: SLASH,
  go: SLASH,
  java: SLASH,
  kt: SLASH,
  swift: SLASH,
  c: SLASH,
  h: SLASH,
  cc: SLASH,
  cpp: SLASH,
  hpp: SLASH,
  cs: SLASH,
  scala: SLASH,
  zig: SLASH,
  dart: SLASH,
  proto: SLASH,
  graphql: HASH,
  py: HASH,
  sh: HASH,
  bash: HASH,
  zsh: HASH,
  nix: HASH,
  yaml: HASH,
  yml: HASH,
  toml: HASH,
  rb: HASH,
  tf: HASH,
  hcl: HASH,
  just: HASH,
  mk: HASH,
  sql: DASH,
  lua: DASH,
  hs: DASH,
};

const SYNTAX_BY_BASENAME: Record<string, CommentSyntax> = {
  justfile: HASH,
  Justfile: HASH,
  Makefile: HASH,
  Dockerfile: HASH,
  '.envrc': HASH,
};

export function syntaxFor(path: string): CommentSyntax | undefined {
  const basename = path.split('/').pop() ?? path;
  if (SYNTAX_BY_BASENAME[basename]) {
    return SYNTAX_BY_BASENAME[basename];
  }
  const extension = basename.includes('.') ? basename.split('.').pop()! : '';
  return SYNTAX_BY_EXTENSION[extension];
}

// Text tooling reads is code, not prose for a person.
const DIRECTIVE =
  /^(biome-ignore|eslint-|@ts-|prettier-ignore|istanbul |c8 |noqa|type: ?ignore|pylint:|shellcheck |nolint|clippy::|rustfmt::|region\b|endregion\b|SPDX-|Copyright |@vite-ignore|webpackChunkName|language=|eslint |tslint:|jscpd:|deno-lint-ignore|!)/;

export function isDirective(text: string): boolean {
  return DIRECTIVE.test(text.trim());
}

/** Paths and line numbers (1-based, new side) of every line a unified diff adds. */
export function addedLines(diff: string): Map<string, Set<number>> {
  const added = new Map<string, Set<number>>();
  let path: string | undefined;
  let newLine = 0;
  for (const raw of diff.split('\n')) {
    if (raw.startsWith('+++ ')) {
      const target = raw.slice(4).trim();
      path = target === '/dev/null' ? undefined : target.replace(/^b\//, '');
      if (path && !added.has(path)) {
        added.set(path, new Set());
      }
      continue;
    }
    const hunk = raw.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (hunk) {
      newLine = Number(hunk[1]);
      continue;
    }
    if (!path || raw.startsWith('--- ') || raw.startsWith('\\')) {
      continue;
    }
    if (raw.startsWith('+')) {
      added.get(path)!.add(newLine);
      newLine++;
    } else if (raw.startsWith(' ')) {
      newLine++;
    }
  }
  return added;
}

/** Column where a line comment starts outside any string literal, or -1. */
export function lineCommentColumn(line: string, syntax: CommentSyntax): number {
  let quote: string | undefined;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (quote) {
      if (char === '\\') {
        i++;
      } else if (char === quote) {
        quote = undefined;
      }
      continue;
    }
    if (syntax.quotes.includes(char)) {
      quote = char;
      continue;
    }
    for (const marker of syntax.line) {
      if (line.startsWith(marker, i)) {
        return i;
      }
    }
    if (syntax.block && line.startsWith(syntax.block[0], i)) {
      return i;
    }
  }
  return -1;
}

export type CommentBlock = {
  path: string;
  /** 1-based, inclusive. */
  startLine: number;
  endLine: number;
  /** `own-line` comments sit above or inside code; `trailing` ones end a code line. */
  placement: 'own-line' | 'trailing';
  text: string;
};

function stripMarkers(raw: string, syntax: CommentSyntax): string {
  let text = raw.trim();
  if (syntax.block) {
    text = text
      .replace(/^\/\*+!?/, '')
      .replace(/\*+\/$/, '')
      .replace(/^\*(?!\/)/, '');
  }
  for (const marker of syntax.line) {
    if (!text.startsWith(marker)) {
      continue;
    }
    text = text.slice(marker.length);
    // Rust and TS doc markers: `///` and `//!`.
    if (marker === '//') {
      text = text.replace(/^[/!]/, '');
    }
  }
  return text.trim();
}

/** Every comment block in a file. Consecutive own-line comments form one block. */
export function commentBlocks(path: string, source: string): CommentBlock[] {
  const syntax = syntaxFor(path);
  if (!syntax) {
    return [];
  }
  const lines = source.split('\n');
  const blocks: CommentBlock[] = [];
  let open: { start: number; texts: string[]; inBlockComment: boolean } | undefined;

  const close = (endLine: number) => {
    if (!open) {
      return;
    }
    const text = open.texts.join('\n').trim();
    if (text && !isDirective(text)) {
      blocks.push({ path, startLine: open.start, endLine, placement: 'own-line', text });
    }
    open = undefined;
  };

  for (let index = 0; index < lines.length; index++) {
    const lineNumber = index + 1;
    const line = lines[index];
    const trimmed = line.trim();

    if (open?.inBlockComment) {
      open.texts.push(stripMarkers(trimmed, syntax));
      if (syntax.block && trimmed.includes(syntax.block[1])) {
        open.inBlockComment = false;
      }
      continue;
    }

    const column = lineCommentColumn(line, syntax);
    if (column === -1) {
      close(lineNumber - 1);
      continue;
    }

    const ownLine = line.slice(0, column).trim() === '';
    const raw = line.slice(column);
    const opensBlockComment =
      syntax.block !== undefined && raw.startsWith(syntax.block[0]) && !raw.includes(syntax.block[1], 2);

    if (!ownLine) {
      close(lineNumber - 1);
      const text = stripMarkers(raw, syntax);
      if (text && !isDirective(text)) {
        blocks.push({ path, startLine: lineNumber, endLine: lineNumber, placement: 'trailing', text });
      }
      continue;
    }

    if (trimmed === '#' || trimmed === '//' || trimmed === '///' || trimmed === '//!') {
      if (open) {
        open.texts.push('');
      }
      continue;
    }
    if (isDirective(stripMarkers(raw, syntax))) {
      close(lineNumber - 1);
      continue;
    }
    if (!open) {
      open = { start: lineNumber, texts: [], inBlockComment: false };
    }
    open.texts.push(stripMarkers(raw, syntax));
    if (opensBlockComment) {
      open.inBlockComment = true;
    }
  }
  close(lines.length);
  return blocks;
}

/** The lines a comment speaks about: the code under an own-line block, the line a trailing one ends. */
export function codeContext(source: string, block: CommentBlock, linesBefore = 4, linesAfter = 14): string {
  const lines = source.split('\n');
  const from = Math.max(0, block.startLine - 1 - linesBefore);
  const to = Math.min(lines.length, block.endLine + linesAfter);
  return lines.slice(from, to).join('\n');
}

/** Non-blank code lines below an own-line block, up to the next blank line or comment. */
export function linesGoverned(source: string, block: CommentBlock, syntax: CommentSyntax): number {
  if (block.placement === 'trailing') {
    return 1;
  }
  const lines = source.split('\n');
  let count = 0;
  for (let index = block.endLine; index < lines.length; index++) {
    const line = lines[index];
    if (line.trim() === '') {
      break;
    }
    const column = lineCommentColumn(line, syntax);
    if (column !== -1 && line.slice(0, column).trim() === '') {
      break;
    }
    count++;
  }
  return count;
}

const HISTORY_MARKERS: [string, RegExp][] = [
  ['issue or PR number', /(^|[\s(])(?:[\w.-]+\/[\w.-]+)?#\d{2,}\b/],
  ['commit sha', /\b[0-9a-f]{7,40}\b(?=.*\b(commit|sha)\b)|\b(commit|sha) [0-9a-f]{7,40}\b/i],
  ['finding or ticket id', /\b(?:[A-Z]{2,}-\d+|f-[0-9a-f]{6,})\b/],
  [
    'the past',
    /\b(as before|than before|used to|previously|no longer|anymore|any more|now that|legacy|retired|was replaced|until now|the old\b|the original\b|goes away|will be removed|remove once|temporar(?:y|ily))\b/i,
  ],
];

/** Words and references that tie a comment to the change that wrote it rather than to the code. */
export function historyMarkers(text: string): string[] {
  return HISTORY_MARKERS.filter(([, pattern]) => pattern.test(text)).map(([name]) => name);
}

export type Signals = {
  restates: number;
  history: number;
  alternative: number;
  intoCode: number;
  duplicate: number | null;
  value: { score: number; confidence: number };
  historyMarkers: string[];
};

export type Action = 'remove' | 'move-to-commit' | 'into-code' | 'dedupe' | 'trim' | 'keep';

export type Thresholds = {
  /** A Noul at or above this is a finding. */
  flag: number;
  /** A Noul inside [low, high) is left to the reader's judgement. */
  uncertainLow: number;
  uncertainHigh: number;
  /** A value Score below this means deleting the comment costs the reader nothing. */
  valueFloor: number;
  /** A comment longer than this many times the code it governs reads as an essay. */
  essayRatio: number;
  valueConfidenceFloor: number;
};

export const DEFAULT_THRESHOLDS: Thresholds = {
  flag: 0.7,
  uncertainLow: 0.35,
  uncertainHigh: 0.7,
  valueFloor: 0.75,
  essayRatio: 1.5,
  valueConfidenceFloor: 0.5,
};

/**
 * `uncertain` names the signals that could flip the decision, and only those:
 * on a kept comment the near-threshold ones, on a changed comment none unless
 * a low-confidence value Score is the sole reason to remove it.
 */
export type Verdict = { actions: Action[]; uncertain: string[] };

export function verdict(
  signals: Signals,
  shape: { commentLines: number; codeLines: number },
  thresholds: Thresholds = DEFAULT_THRESHOLDS,
): Verdict {
  const actions = new Set<Action>();
  const uncertain: string[] = [];
  const nouls: [keyof Signals, number | null, Action][] = [
    ['restates', signals.restates, 'remove'],
    ['history', signals.history, 'move-to-commit'],
    ['intoCode', signals.intoCode, 'into-code'],
    ['duplicate', signals.duplicate, 'dedupe'],
    ['alternative', signals.alternative, 'trim'],
  ];
  for (const [name, probability, action] of nouls) {
    if (probability === null) {
      continue;
    }
    if (probability >= thresholds.flag) {
      actions.add(action);
    } else if (probability >= thresholds.uncertainLow && probability < thresholds.uncertainHigh) {
      uncertain.push(name);
    }
  }
  // A marker alone misfires on "legacy" as a product name; Jev alone misses a bare `#21471`.
  if (signals.historyMarkers.length > 0 && signals.history >= thresholds.uncertainLow) {
    actions.add('move-to-commit');
    const index = uncertain.indexOf('history');
    if (index !== -1) {
      uncertain.splice(index, 1);
    }
  }
  const removedOnValueAlone = signals.value.score < thresholds.valueFloor && actions.size === 0;
  if (signals.value.score < thresholds.valueFloor) {
    actions.add('remove');
  }
  const valueUnsure = signals.value.confidence < thresholds.valueConfidenceFloor;
  if (shape.commentLines > 3 && shape.commentLines > thresholds.essayRatio * Math.max(1, shape.codeLines)) {
    actions.add('trim');
  }
  if (actions.has('remove')) {
    actions.delete('trim');
    actions.delete('dedupe');
  }
  if (actions.size === 0) {
    if (valueUnsure) {
      uncertain.push('value');
    }
    if (signals.historyMarkers.length > 0 && !uncertain.includes('history')) {
      uncertain.push('history');
    }
    return { actions: ['keep'], uncertain };
  }
  return { actions: [...actions], uncertain: removedOnValueAlone && valueUnsure ? ['value'] : [] };
}
