#!/usr/bin/env node
// Scores whether a diff solves one problem and how the functions it touches
// are composed, with Jev. Usage and the reasoning that follows a run are in
// ../SKILL.md.
//
//   node scope-score.ts [--base <ref>] [--diff <file>] [--repo <dir>] [--body <file>] [--concerns <json>] [--text]
//   node scope-score.ts --calibrate <labelled.json>
//
// Node strips the types itself, so this runs from the store with no build step.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

import {
  type ConcernOrder,
  concernOrder,
  DEFAULT_THRESHOLDS,
  type FileDiff,
  type FunctionUnit,
  functionsTouched,
  isGenerated,
  mechanicalLines,
  parseDiff,
  type ScopeVerdict,
  scopeVerdict,
  type UnitAction,
  type UnitSignals,
  unitVerdict,
} from './scope.ts';

const JEV_URL = 'https://api.typesafe.ai/v1/systemone';
const CONCURRENCY = 6;
const MAX_ATTEMPTS = 5;
const FILE_DIFF_CHARS_MAX = 8000;
const FUNCTION_CHARS_MAX = 6000;
const UNITS_MAX = 60;
const NEIGHBOURS_MAX = 8;
// A file this large is assigned hunk by hunk, so two concerns sharing it come apart.
const HUNK_PIECES_LINES_MIN = 120;

const DESCRIPTION_QUESTIONS = {
  multipleProblems: {
    type: 'noul',
    instructions:
      'Does `description` set out to solve more than one problem, where a reviewer could accept the fix for one and reject the fix for another?',
    criteria: {
      true: 'Two or more distinct problems, such as a bug fix plus a refactor, a new feature plus an unrelated cleanup, or a fix plus the tooling built to measure it.',
      false:
        'One problem. Several bullets that each describe a part of the same fix, or a mechanical change carried through many files, still count as one.',
    },
  },
} as const;

const UNIT_QUESTIONS = {
  severalJobs: {
    type: 'noul',
    instructions:
      'Does `function` interleave two or more separate responsibilities that each deserve their own name, so a reader has to track both at once?',
    criteria: {
      true: 'Bookkeeping or accounting woven through the main work, coordination logic mixed with the computation it coordinates, or a parse followed by an unrelated write.',
      false:
        'One responsibility. Guard clauses, early returns, a lookup followed by its use, converting an input and acting on it, logging around the work, or a loop applying one kind of step all count as one job.',
    },
  },
  invariantInProse: {
    type: 'noul',
    instructions:
      'Does `function` keep an invariant through comments or through the caller remembering a rule, where a type, a guard value whose destructor runs the second step, a constructor that rejects bad input, or an enum could enforce it?',
    criteria: {
      true: 'A pairing such as charge then settle or acquire then release, a flag that must be set before or cleared after a step, an ordering of calls, or a value range that only a comment protects.',
      false: 'The types, ownership and control flow already enforce every rule the function relies on.',
    },
  },
  flagParameter: {
    type: 'noul',
    instructions:
      'Does `function` take a parameter whose value switches it between different behaviours, such as a boolean or mode flag, where two functions or an enum would make each call site say what it means?',
  },
  duplicate: {
    type: 'noul',
    instructions:
      'Does an entry in `other_functions` repeat the same sequence of steps as `function`, apart from names and the values it works on?',
  },
} as const;

type Answer =
  | { type: 'noul'; noul: number }
  | { type: 'choice'; choice: string; probabilities: Record<string, number>; confidence: number };

async function askJev(state: unknown, questions: Record<string, unknown>): Promise<Record<string, Answer>> {
  const key = process.env.TYPESAFE_API_KEY;
  if (!key) {
    throw new Error('TYPESAFE_API_KEY is not set');
  }
  for (let attempt = 1; ; attempt++) {
    const response = await fetch(JEV_URL, {
      method: 'POST',
      headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: 'jev-latest', state, questions }),
      signal: AbortSignal.timeout(60_000),
    });
    if (response.ok) {
      return ((await response.json()) as { answers: Record<string, Answer> }).answers;
    }
    const retryable = response.status === 429 || response.status === 529 || response.status >= 500;
    if (!retryable || attempt === MAX_ATTEMPTS) {
      throw new Error(`Jev answered ${response.status}: ${await response.text()}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
  }
}

const noulOf = (answers: Record<string, Answer>, name: string) =>
  (answers[name] as { noul: number } | undefined)?.noul ?? null;

async function mapLimited<T, R>(items: T[], limit: number, run: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await run(items[index]);
    }
  });
  await Promise.all(workers);
  return results;
}

function readDiff(repo: string, base: string | undefined, diffFile: string | undefined): string {
  if (diffFile) {
    return readFileSync(diffFile, 'utf8');
  }
  const git = (...args: string[]) =>
    execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8', maxBuffer: 1 << 28 });
  const mergeBase = git('merge-base', base ?? 'origin/HEAD', 'HEAD').trim();
  return git('diff', '--no-color', '--no-ext-diff', '-M', mergeBase);
}

function readSource(repo: string, path: string): string | undefined {
  try {
    return readFileSync(join(repo, path), 'utf8');
  } catch {
    return undefined;
  }
}

function fileDiffText(file: FileDiff): string {
  const text = file.hunks.map((hunk) => hunk.lines.map((line) => `${line.kind}${line.text}`).join('\n')).join('\n@@\n');
  return text.length > FILE_DIFF_CHARS_MAX ? `${text.slice(0, FILE_DIFF_CHARS_MAX)}\n[truncated]` : text;
}

type Concern = { id: string; statement: string };

type FileScope = {
  path: string;
  added: number;
  removed: number;
  generated: boolean;
  mechanicalLines: number;
  handLines: number;
};

/** The unit a concern is assigned to: a whole file, or one hunk of a large one. */
type Piece = {
  path: string;
  /** First new-side line of the hunk, or 1 for a whole file. */
  line: number;
  lines: number;
  diff: string;
  addedText: string;
  concern?: { choice: string; confidence: number };
};

function piecesOf(file: FileDiff, handLines: number): Piece[] {
  const addedText = (hunks: FileDiff['hunks']) =>
    hunks.flatMap((hunk) => hunk.lines.filter((line) => line.kind === '+').map((line) => line.text)).join('\n');
  if (handLines < HUNK_PIECES_LINES_MIN || file.hunks.length < 2) {
    return [{ path: file.path, line: 1, lines: handLines, diff: fileDiffText(file), addedText: addedText(file.hunks) }];
  }
  return file.hunks.map((hunk) => {
    const text = hunk.lines.map((line) => `${line.kind}${line.text}`).join('\n');
    return {
      path: file.path,
      line: hunk.lines.find((line) => line.newLine !== undefined)?.newLine ?? 1,
      lines: hunk.lines.filter((line) => line.kind !== ' ').length,
      diff: text.length > FILE_DIFF_CHARS_MAX ? `${text.slice(0, FILE_DIFF_CHARS_MAX)}\n[truncated]` : text,
      addedText: addedText([hunk]),
    };
  });
}

async function scoreUnits(units: FunctionUnit[]) {
  const ranked = [...units].sort((a, b) => b.bodyLines - a.bodyLines).slice(0, UNITS_MAX);
  return mapLimited(ranked, CONCURRENCY, async (unit) => {
    const others = units.filter((other) => other !== unit);
    const neighbours = [
      ...others.filter((other) => other.path === unit.path),
      ...others.filter((other) => other.path !== unit.path),
    ]
      .slice(0, NEIGHBOURS_MAX)
      .map((other) => other.text.slice(0, 800));
    const { duplicate, ...always } = UNIT_QUESTIONS;
    const answers = await askJev(
      {
        function: unit.text.slice(0, FUNCTION_CHARS_MAX),
        path: unit.path,
        other_functions: neighbours,
      },
      neighbours.length > 0 ? { ...always, duplicate } : always,
    );
    const signals: UnitSignals = {
      severalJobs: noulOf(answers, 'severalJobs')!,
      invariantInProse: noulOf(answers, 'invariantInProse')!,
      flagParameter: noulOf(answers, 'flagParameter')!,
      duplicate: noulOf(answers, 'duplicate'),
    };
    const { text: _text, ...shape } = unit;
    return { ...shape, signals, ...unitVerdict(signals, unit) };
  });
}

async function audit(repo: string, diff: string, body: string | undefined, concerns: Concern[] | undefined) {
  const files = parseDiff(diff);
  const mechanical = mechanicalLines(files);
  const sources = new Map<string, string | undefined>(files.map((file) => [file.path, readSource(repo, file.path)]));

  const fileScopes: FileScope[] = files.map((file) => {
    const generated = isGenerated(file.path, sources.get(file.path));
    const mechanicalCount = generated ? 0 : (mechanical.get(file.path) ?? 0);
    const changed = file.added + file.removed;
    return {
      path: file.path,
      added: file.added,
      removed: file.removed,
      generated,
      mechanicalLines: mechanicalCount,
      handLines: generated ? 0 : Math.max(0, changed - mechanicalCount),
    };
  });
  const handLines = fileScopes.reduce((sum, file) => sum + file.handLines, 0);

  let multipleProblems: number | null = null;
  if (body) {
    const answers = await askJev({ description: body }, DESCRIPTION_QUESTIONS);
    multipleProblems = noulOf(answers, 'multipleProblems');
  }

  let linesByConcern: Map<string, number> | null = null;
  let pieces: Piece[] = [];
  let order: ConcernOrder = { before: [], entangled: [] };
  if (concerns && concerns.length > 0) {
    const criteria: Record<string, string> = Object.fromEntries(
      concerns.map((concern) => [concern.id, concern.statement]),
    );
    criteria.wiring =
      'Connects the other concerns without a decision of its own: a constructor argument, a re-export, a config field passed through, a call site updated for a new signature.';
    criteria.unrelated = 'Serves none of the listed concerns.';
    pieces = fileScopes
      .filter((scope) => scope.handLines > 0)
      .flatMap((scope) => piecesOf(files.find((candidate) => candidate.path === scope.path)!, scope.handLines));
    await mapLimited(pieces, CONCURRENCY, async (piece) => {
      const answers = await askJev(
        { file: piece.path, diff: piece.diff },
        {
          concern: {
            type: 'choice',
            instructions:
              'Which concern does the change to `file`, shown in `diff`, serve? A test, test helper or fixture serves the concern whose behaviour it checks.',
            criteria,
          },
        },
      );
      const answer = answers.concern as { choice: string; confidence: number };
      piece.concern = { choice: answer.choice, confidence: answer.confidence };
    });
    linesByConcern = new Map();
    const addedTextByConcern = new Map<string, string>();
    for (const piece of pieces) {
      const concern = piece.concern!.choice;
      linesByConcern.set(concern, (linesByConcern.get(concern) ?? 0) + piece.lines);
      addedTextByConcern.set(concern, `${addedTextByConcern.get(concern) ?? ''}\n${piece.addedText}`);
    }
    addedTextByConcern.delete('wiring');
    addedTextByConcern.delete('unrelated');
    order = concernOrder(addedTextByConcern);
  }

  const units: FunctionUnit[] = [];
  for (const file of files) {
    const source = sources.get(file.path);
    const scope = fileScopes.find((candidate) => candidate.path === file.path)!;
    if (!source || scope.generated || scope.handLines === 0) {
      continue;
    }
    const added = new Set(
      file.hunks.flatMap((hunk) => hunk.lines.filter((line) => line.kind === '+').map((line) => line.newLine!)),
    );
    units.push(...functionsTouched(file.path, source, added));
  }
  const scoredUnits = await scoreUnits(units);

  const verdict: ScopeVerdict = scopeVerdict({ handLines, multipleProblems, linesByConcern });
  return {
    summary: {
      files: files.length,
      changedLines: fileScopes.reduce((sum, file) => sum + file.added + file.removed, 0),
      generatedLines: fileScopes
        .filter((file) => file.generated)
        .reduce((sum, file) => sum + file.added + file.removed, 0),
      mechanicalLines: fileScopes.reduce((sum, file) => sum + file.mechanicalLines, 0),
      handLines,
      multipleProblems,
      ...verdict,
      thresholds: DEFAULT_THRESHOLDS,
    },
    concerns: linesByConcern ? Object.fromEntries(linesByConcern) : null,
    order: {
      before: order.before.map(([owner, user]) => `${owner} before ${user}`),
      entangled: order.entangled.map(([first, second]) => `${first} and ${second}`),
    },
    files: fileScopes,
    pieces: pieces.map(({ diff: _diff, addedText: _added, ...piece }) => piece),
    functions: scoredUnits,
  };
}

function renderText(report: Awaited<ReturnType<typeof audit>>): string {
  const summary = report.summary;
  const fmt = (value: number | null) => (value === null ? '-' : value.toFixed(2));
  const out: string[] = [
    `${summary.files} files, ${summary.changedLines} changed lines: ${summary.generatedLines} generated, ${summary.mechanicalLines} mechanical, ${summary.handLines} hand-written.`,
    `Description: multiple problems ${fmt(summary.multipleProblems)}.`,
    `Verdict: ${summary.verdict}${summary.reasons.length ? ` (${summary.reasons.join('; ')})` : ''}`,
  ];
  if (report.concerns) {
    out.push('', 'Hand-written lines per concern:');
    for (const [concern, lines] of Object.entries(report.concerns)) {
      out.push(`  ${concern}: ${lines}`);
      for (const piece of report.pieces.filter((candidate) => candidate.concern?.choice === concern)) {
        out.push(`    ${piece.path}:${piece.line} ${piece.lines} (conf ${piece.concern!.confidence.toFixed(2)})`);
      }
    }
    if (report.order.before.length || report.order.entangled.length) {
      out.push(
        '',
        'Order:',
        ...report.order.before.map((edge) => `  ${edge}`),
        ...report.order.entangled.map((pair) => `  ${pair} use each other's items`),
      );
    }
  }
  out.push('', 'Functions:');
  for (const unit of report.functions) {
    if (unit.actions.includes('keep') && unit.uncertain.length === 0) {
      continue;
    }
    const { severalJobs, invariantInProse, flagParameter, duplicate } = unit.signals;
    out.push(
      `  ${unit.path}:${unit.startLine}-${unit.endLine} ${unit.name} [${unit.actions.join(', ')}]${unit.uncertain.length ? ` uncertain: ${unit.uncertain.join(', ')}` : ''}`,
      `    several-jobs ${severalJobs.toFixed(2)} invariant-in-prose ${invariantInProse.toFixed(2)} flag ${flagParameter.toFixed(2)} duplicate ${fmt(duplicate)} | ${unit.bodyLines} lines, ${unit.params} params, nesting ${unit.maxNesting}, ${unit.commentLines} comment lines`,
    );
  }
  return out.join('\n');
}

type LabelledCase =
  | { kind: 'description'; name: string; description: string; expect: 'one-problem' | 'split' }
  | { kind: 'function'; name: string; path: string; code: string; others?: string[]; expect: UnitAction[] };

async function calibrate(file: string): Promise<string> {
  const cases = JSON.parse(readFileSync(file, 'utf8')) as LabelledCase[];
  const lines = await mapLimited(cases, CONCURRENCY, async (labelled) => {
    if (labelled.kind === 'description') {
      const answers = await askJev({ description: labelled.description }, DESCRIPTION_QUESTIONS);
      const multiple = noulOf(answers, 'multipleProblems')!;
      const got = multiple >= DEFAULT_THRESHOLDS.flag ? 'split' : 'one-problem';
      return {
        agrees: got === labelled.expect,
        line: `${labelled.name}: expect ${labelled.expect} got ${got}\n     multiple ${multiple.toFixed(2)}`,
      };
    }
    const [unit] = functionsTouched(
      labelled.path,
      labelled.code,
      new Set(labelled.code.split('\n').map((_, index) => index + 1)),
    );
    if (!unit) {
      return { agrees: false, line: `${labelled.name}: no function found` };
    }
    const others = labelled.others ?? [];
    const { duplicate, ...always } = UNIT_QUESTIONS;
    const answers = await askJev(
      { function: unit.text, path: labelled.path, other_functions: others },
      others.length > 0 ? { ...always, duplicate } : always,
    );
    const signals: UnitSignals = {
      severalJobs: noulOf(answers, 'severalJobs')!,
      invariantInProse: noulOf(answers, 'invariantInProse')!,
      flagParameter: noulOf(answers, 'flagParameter')!,
      duplicate: noulOf(answers, 'duplicate'),
    };
    const { actions, uncertain } = unitVerdict(signals, unit);
    const expectKeep = labelled.expect.includes('keep');
    const agrees = expectKeep ? actions.includes('keep') : !actions.includes('keep');
    return {
      agrees,
      line: `${labelled.name}: expect [${labelled.expect}] got [${actions}]${uncertain.length ? ` ?${uncertain}` : ''}\n     several-jobs ${signals.severalJobs.toFixed(2)} invariant-in-prose ${signals.invariantInProse.toFixed(2)} flag ${signals.flagParameter.toFixed(2)} duplicate ${signals.duplicate?.toFixed(2) ?? '-'} | ${unit.bodyLines} lines`,
    };
  });
  const agreed = lines.filter((result) => result.agrees).length;
  return [
    ...lines.map((result) => `${result.agrees ? 'ok  ' : 'MISS'} ${result.line}`),
    '',
    `${agreed}/${lines.length} agree.`,
  ].join('\n');
}

const { values } = parseArgs({
  options: {
    base: { type: 'string' },
    diff: { type: 'string' },
    repo: { type: 'string', default: '.' },
    body: { type: 'string' },
    concerns: { type: 'string' },
    text: { type: 'boolean', default: false },
    calibrate: { type: 'string' },
  },
});

if (values.calibrate) {
  process.stdout.write(`${await calibrate(values.calibrate)}\n`);
} else {
  const report = await audit(
    values.repo!,
    readDiff(values.repo!, values.base, values.diff),
    values.body ? readFileSync(values.body, 'utf8') : undefined,
    values.concerns ? (JSON.parse(readFileSync(values.concerns, 'utf8')) as Concern[]) : undefined,
  );
  process.stdout.write(`${values.text ? renderText(report) : JSON.stringify(report, null, 2)}\n`);
}
