#!/usr/bin/env node
// Scores the comments a diff adds with Jev and prints what each one should
// become. Usage and the reasoning that follows a run are in ../SKILL.md.
//
//   node comment-score.ts [--base <ref>] [--diff <file>] [--repo <dir>] [--text]
//   node comment-score.ts --calibrate <labelled.json>
//
// Node strips the types itself, so this runs from the store with no build step.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

import {
  type Action,
  addedLines,
  type CommentBlock,
  codeContext,
  commentBlocks,
  DEFAULT_THRESHOLDS,
  historyMarkers,
  linesGoverned,
  type Signals,
  syntaxFor,
  verdict,
} from './comments.ts';

const JEV_URL = 'https://api.typesafe.ai/v1/systemone';
const CONCURRENCY = 6;
const MAX_ATTEMPTS = 5;
const OTHER_COMMENTS_CHARS_MAX = 6000;

// Each question names one failure mode, so a yes is a finding and code decides
// what a combination means. `comment`, `code` and `other_comments` are the
// state fields of every request.
const QUESTIONS = {
  restates: {
    type: 'noul',
    instructions:
      'Can a reader who reads `code` fluently learn everything `comment` says from the identifiers, types, signatures and statements in `code` alone?',
    criteria: {
      true: 'Every fact in the comment is already expressed by a name or a statement in the code, possibly in other words. Paraphrasing a function, field or variable name counts.',
      false:
        'The comment states at least one fact the code does not express: a constraint imposed from outside this code, a reason a non-obvious choice is required, a unit, a hazard, or an invariant other code relies on.',
    },
  },
  history: {
    type: 'noul',
    instructions:
      'Does `comment` narrate how this code or the system around it changed over time: what an earlier implementation or a retired component did, what the code used to do, a migration in progress, when the code will be removed, or a ticket, issue, PR, incident or commit that led to it?',
    criteria: {
      true: 'Part of the comment only makes sense to someone who knows the previous state or the change that introduced the code.',
      false:
        'The comment describes the system as it is now. Old firmware, devices, versions or clients that are still in service today are present-tense facts, not history.',
    },
  },
  alternative: {
    type: 'noul',
    instructions:
      'Does `comment` spend its words on an approach the code does not use, what that approach would allow or cost, or why it was not chosen, beyond stating the constraint the code satisfies?',
    criteria: {
      true: 'The comment argues for the chosen design, for example "keeping X as fields rather than a string lets a caller...", the kind of justification a reviewer asks for once.',
      false:
        'The comment states a constraint, limit or behaviour the code must respect, even when it names what that constraint rules out in a clause.',
    },
  },
  intoCode: {
    type: 'noul',
    instructions:
      'Could the code carry what `comment` says without the comment, through a more descriptive name, an extracted function or constant with a descriptive name, a more precise type, or an assertion?',
    criteria: {
      true: 'A specific rename, extraction, type or assertion would make the comment unnecessary.',
      false:
        'The comment carries knowledge no name, type or assertion can express, such as the behaviour of an external system or why a constraint exists.',
    },
  },
  duplicate: {
    type: 'noul',
    instructions: 'Does an entry in `other_comments` already state the main fact that `comment` states?',
  },
  value: {
    type: 'score',
    instructions: 'What does a maintainer who reads `code` fluently lose if `comment` is deleted?',
    criteria: [
      'Nothing. The names and statements in the code already say it, or the comment narrates the past.',
      'A convenience. The comment summarises or labels something the reader would work out from the code in under a minute.',
      'A fact the code cannot show. The comment states a constraint from outside this code, a hazard, a unit, or an invariant that other code depends on, and the reader could break it without the comment.',
    ],
  },
} as const;

type Answer = { type: 'noul'; noul: number } | { type: 'score'; score: number; confidence: number };

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

async function signalsFor(comment: string, code: string, otherComments: string[]): Promise<Signals> {
  const { duplicate, ...always } = QUESTIONS;
  const questions = otherComments.length > 0 ? { ...always, duplicate } : always;
  const answers = await askJev({ comment, code, other_comments: otherComments }, questions);
  const noul = (name: string) => (answers[name] as { noul: number } | undefined)?.noul ?? null;
  const value = answers.value as { score: number; confidence: number };
  return {
    restates: noul('restates')!,
    history: noul('history')!,
    alternative: noul('alternative')!,
    intoCode: noul('intoCode')!,
    duplicate: noul('duplicate'),
    value: { score: value.score, confidence: value.confidence },
    historyMarkers: historyMarkers(comment),
  };
}

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

function otherCommentsFor(block: CommentBlock, fileBlocks: CommentBlock[], addedElsewhere: CommentBlock[]): string[] {
  const others = [...fileBlocks, ...addedElsewhere].filter(
    (other) => !(other.path === block.path && other.startLine === block.startLine),
  );
  const texts: string[] = [];
  let chars = 0;
  for (const other of others) {
    const entry = `${other.path}:${other.startLine}: ${other.text}`;
    if (chars + entry.length > OTHER_COMMENTS_CHARS_MAX) {
      break;
    }
    texts.push(entry);
    chars += entry.length;
  }
  return texts;
}

function readDiff(repo: string, base: string | undefined, diffFile: string | undefined): string {
  if (diffFile) {
    return readFileSync(diffFile, 'utf8');
  }
  const git = (...args: string[]) =>
    execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8', maxBuffer: 1 << 28 });
  const baseRef = base ?? 'origin/HEAD';
  const mergeBase = git('merge-base', baseRef, 'HEAD').trim();
  // Against the working tree, so uncommitted edits are audited before they are committed.
  return git('diff', '--no-color', '--no-ext-diff', '--unified=0', mergeBase);
}

type Scored = CommentBlock & {
  commentLines: number;
  codeLines: number;
  signals: Signals;
  actions: Action[];
  uncertain: string[];
};

async function audit(repo: string, diff: string) {
  const added = addedLines(diff);
  const blocksByFile = new Map<string, CommentBlock[]>();
  const sources = new Map<string, string>();
  const targets: CommentBlock[] = [];

  for (const [path, lines] of added) {
    if (!syntaxFor(path) || lines.size === 0) {
      continue;
    }
    let source: string;
    try {
      source = readFileSync(join(repo, path), 'utf8');
    } catch {
      continue;
    }
    sources.set(path, source);
    const blocks = commentBlocks(path, source);
    blocksByFile.set(path, blocks);
    for (const block of blocks) {
      for (let line = block.startLine; line <= block.endLine; line++) {
        if (lines.has(line)) {
          targets.push(block);
          break;
        }
      }
    }
  }

  const scored: Scored[] = await mapLimited(targets, CONCURRENCY, async (block) => {
    const source = sources.get(block.path)!;
    const addedElsewhere = targets.filter((other) => other.path !== block.path);
    const signals = await signalsFor(
      block.text,
      codeContext(source, block),
      otherCommentsFor(block, blocksByFile.get(block.path)!, addedElsewhere),
    );
    const commentLines = block.endLine - block.startLine + 1;
    const codeLines = linesGoverned(source, block, syntaxFor(block.path)!);
    return { ...block, commentLines, codeLines, signals, ...verdict(signals, { commentLines, codeLines }) };
  });

  const files = [...added]
    .filter(([path]) => sources.has(path))
    .map(([path, lines]) => {
      const source = sources.get(path)!.split('\n');
      const commentLineSet = new Set<number>();
      for (const block of blocksByFile.get(path)!) {
        for (let line = block.startLine; line <= block.endLine; line++) {
          commentLineSet.add(line);
        }
      }
      let commentLines = 0;
      let codeLines = 0;
      for (const line of lines) {
        if (commentLineSet.has(line)) {
          commentLines++;
        } else if (source[line - 1]?.trim()) {
          codeLines++;
        }
      }
      return { path, commentLines, codeLines, ratio: codeLines ? +(commentLines / codeLines).toFixed(2) : null };
    })
    .filter((file) => file.commentLines > 0);

  const flagged = scored.filter((comment) => !comment.actions.includes('keep'));
  return {
    summary: {
      comments: scored.length,
      flagged: flagged.length,
      uncertain: scored.filter((comment) => comment.uncertain.length > 0).length,
      thresholds: DEFAULT_THRESHOLDS,
    },
    files,
    comments: scored,
  };
}

function renderText(report: Awaited<ReturnType<typeof audit>>): string {
  const out: string[] = [
    `${report.summary.comments} added comment blocks, ${report.summary.flagged} flagged, ${report.summary.uncertain} with uncertain signals.`,
    '',
    'Comment lines per added code line:',
    ...report.files.map(
      (file) => `  ${file.path}: ${file.commentLines}/${file.codeLines} (${file.ratio ?? 'no code'})`,
    ),
    '',
  ];
  for (const comment of report.comments) {
    if (comment.actions.includes('keep') && comment.uncertain.length === 0) {
      continue;
    }
    const { restates, history, alternative, intoCode, duplicate, value } = comment.signals;
    out.push(
      `${comment.path}:${comment.startLine}-${comment.endLine} [${comment.actions.join(', ')}]${comment.uncertain.length ? ` uncertain: ${comment.uncertain.join(', ')}` : ''}`,
      `  restates ${restates.toFixed(2)} history ${history.toFixed(2)} alternative ${alternative.toFixed(2)} into-code ${intoCode.toFixed(2)} duplicate ${duplicate?.toFixed(2) ?? '-'} value ${value.score.toFixed(2)} (conf ${value.confidence.toFixed(2)})${comment.signals.historyMarkers.length ? ` markers: ${comment.signals.historyMarkers.join(', ')}` : ''} lines ${comment.commentLines}/${comment.codeLines}`,
      ...comment.text.split('\n').map((line) => `  | ${line}`),
      '',
    );
  }
  return out.join('\n');
}

type LabelledCase = { name: string; comment: string; code: string; other_comments?: string[]; expect: Action[] };

async function calibrate(file: string) {
  const cases = JSON.parse(readFileSync(file, 'utf8')) as LabelledCase[];
  const results = await mapLimited(cases, CONCURRENCY, async (labelled) => {
    const signals = await signalsFor(labelled.comment, labelled.code, labelled.other_comments ?? []);
    const commentLines = labelled.comment.split('\n').length;
    const codeLines = labelled.code.split('\n').filter((line) => line.trim()).length;
    const { actions, uncertain } = verdict(signals, { commentLines, codeLines });
    const expectKeep = labelled.expect.includes('keep');
    const agrees = expectKeep ? actions.includes('keep') : !actions.includes('keep');
    return { name: labelled.name, expect: labelled.expect, actions, uncertain, agrees, signals };
  });
  const out: string[] = [];
  for (const result of results) {
    const { restates, history, alternative, intoCode, duplicate, value } = result.signals;
    out.push(
      `${result.agrees ? 'ok  ' : 'MISS'} ${result.name}: expect [${result.expect}] got [${result.actions}]${result.uncertain.length ? ` ?${result.uncertain}` : ''}`,
      `     restates ${restates.toFixed(2)} history ${history.toFixed(2)} alternative ${alternative.toFixed(2)} into-code ${intoCode.toFixed(2)} duplicate ${duplicate?.toFixed(2) ?? '-'} value ${value.score.toFixed(2)}/${value.confidence.toFixed(2)}${result.signals.historyMarkers.length ? ` markers: ${result.signals.historyMarkers}` : ''}`,
    );
  }
  const agreed = results.filter((result) => result.agrees).length;
  out.push('', `${agreed}/${results.length} agree on keep versus change.`);
  return out.join('\n');
}

const { values } = parseArgs({
  options: {
    base: { type: 'string' },
    diff: { type: 'string' },
    repo: { type: 'string', default: '.' },
    text: { type: 'boolean', default: false },
    calibrate: { type: 'string' },
  },
});

if (values.calibrate) {
  process.stdout.write(`${await calibrate(values.calibrate)}\n`);
} else {
  const report = await audit(values.repo!, readDiff(values.repo!, values.base, values.diff));
  process.stdout.write(`${values.text ? renderText(report) : JSON.stringify(report, null, 2)}\n`);
}
