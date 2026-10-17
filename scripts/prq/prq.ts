#!/usr/bin/env node
// Lists your open pull requests by who holds the ball, with stacks drawn as
// trees, priority labels, every reviewer's standing and the cached comment and
// scope audits. Usage is in `prq --help`.
//
// Node strips the types itself, so this runs from the store with no build step.
import { execFile, spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseArgs, promisify } from 'node:util';

import { brief } from './brief.ts';
import {
  type Assessment,
  assess,
  keyOf,
  orderByUrgency,
  type PullRequest,
  type Reviewer,
  STATES_BY_URGENCY,
  type State,
  stacks,
} from './classify.ts';
import { startSession } from './session.ts';

const run = promisify(execFile);
const MAX_BUFFER = 1 << 28;
const AUDIT_CONCURRENCY = 2;

const USAGE = `Usage: prq [--all] [--drafts] [--audit] [--plain]
  (no flag)  Your open, non-draft pull requests in the repository of the working directory
  --all      Every repository
  --drafts   Include drafts
  --audit    Run the comment and scope audits (Jev) for every head not audited yet.
             Needs TYPESAFE_API_KEY and a checkout of the repository as the working directory.
  --plain    Print the list instead of opening fzf (the default when stdout is not a terminal)

In fzf: enter opens the pull request, ctrl-r re-requests the reviewers marked ↻,
ctrl-a audits the selected pull request, ctrl-b starts an agent session on the
agents console from a brief of what is open on it (MJ_AGENTS_SESSION holds the console's
__Host-mj_session cookie; without it the console's form opens prefilled and the brief
goes to the clipboard), ctrl-l refetches.`;

const QUERY = `
query($q: String!, $endCursor: String) {
  search(query: $q, type: ISSUE, first: 20, after: $endCursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number title url isDraft body createdAt
        baseRefName headRefName headRefOid mergeable reviewDecision
        repository { nameWithOwner defaultBranchRef { name } }
        labels(first: 20) { nodes { name } }
        reviewRequests(first: 20) {
          nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug } } }
        }
        reviews(last: 50) { nodes { author { login __typename } state submittedAt body } }
        comments(last: 30) { nodes { author { login __typename } createdAt body url } }
        reviewThreads(first: 100) {
          nodes {
            isResolved path
            comments(last: 10) { nodes { author { login __typename } createdAt body url } }
          }
        }
        commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
        timelineItems(last: 50, itemTypes: [REVIEW_REQUESTED_EVENT, HEAD_REF_FORCE_PUSHED_EVENT]) {
          nodes {
            __typename
            ... on ReviewRequestedEvent {
              createdAt
              requestedReviewer { __typename ... on User { login } ... on Team { slug } }
            }
            ... on HeadRefForcePushedEvent { createdAt }
          }
        }
      }
    }
  }
}`;

type Options = { all: boolean; drafts: boolean; repo: string | null };

type Snapshot = {
  me: string;
  options: Options;
  fetchedAt: string;
  prs: PullRequest[];
};

async function gh(...args: string[]): Promise<string> {
  return (await run('gh', args, { maxBuffer: MAX_BUFFER })).stdout;
}

async function currentRepo(): Promise<string | null> {
  try {
    return (await gh('repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner')).trim() || null;
  } catch {
    return null;
  }
}

async function fetchSnapshot(options: Options): Promise<Snapshot> {
  const me = (await gh('api', 'user', '--jq', '.login')).trim();
  let q = 'is:open is:pr author:@me archived:false sort:created-asc';
  if (!options.drafts) {
    q += ' draft:false';
  }
  if (options.repo) {
    q += ` repo:${options.repo}`;
  }
  const pages = JSON.parse(await gh('api', 'graphql', '--paginate', '--slurp', '-f', `query=${QUERY}`, '-f', `q=${q}`));
  const prs: PullRequest[] = pages
    .flatMap((page: { data: { search: { nodes: PullRequest[] } } }) => page.data.search.nodes)
    .filter((pr: PullRequest) => pr.number !== undefined);
  return { me, options, fetchedAt: new Date().toISOString(), prs };
}

type Audit = {
  sha: string;
  at: string;
  comments: { flagged: number; total: number } | null;
  scope: { verdict: string; functionsFlagged: number } | null;
  errors: string[];
};

const cacheRoot = join(process.env.XDG_CACHE_HOME ?? join(homedir(), '.cache'), 'prq', 'audit');
const auditDir = (repo: string) => join(cacheRoot, repo.replace('/', '-'));
const COMMENT_SCORE =
  process.env.PRQ_COMMENT_SCORE ?? join(homedir(), '.claude/skills/comment-audit/scripts/comment-score.ts');
const SCOPE_SCORE = process.env.PRQ_SCOPE_SCORE ?? join(homedir(), '.claude/skills/scope-audit/scripts/scope-score.ts');

function latestAudit(pr: PullRequest): { audit: Audit; stale: boolean } | null {
  let files: string[];
  try {
    files = readdirSync(auditDir(pr.repository.nameWithOwner)).filter((f) => f.startsWith(`${pr.number}-`));
  } catch {
    return null;
  }
  const audits = files
    .map((f) => JSON.parse(readFileSync(join(auditDir(pr.repository.nameWithOwner), f), 'utf8')) as Audit)
    .sort((a, b) => a.at.localeCompare(b.at));
  const exact = audits.find((a) => a.sha === pr.headRefOid);
  if (exact) {
    return { audit: exact, stale: false };
  }
  return audits.length ? { audit: audits.at(-1)!, stale: true } : null;
}

async function git(...args: string[]): Promise<string> {
  return (await run('git', args, { maxBuffer: MAX_BUFFER })).stdout;
}

// The changed files are extracted at the head because the scorers read whole
// files for context and the working tree is elsewhere.
async function writeScorerInputs(pr: PullRequest, sha: string, mergeBase: string, scratch: string) {
  const diffFile = join(scratch, 'diff.patch');
  const bodyFile = join(scratch, 'body.md');
  const tree = join(scratch, 'tree');
  mkdirSync(tree);
  writeFileSync(diffFile, await git('diff', mergeBase, sha));
  writeFileSync(bodyFile, `# ${pr.title}\n\n${pr.body}`);
  const paths = (await git('diff', '--name-only', '--diff-filter=d', '-z', mergeBase, sha)).split('\0').filter(Boolean);
  if (paths.length) {
    await run('sh', ['-c', 'git archive "$0" -- "$@" | tar -x -C "$PRQ_TREE"', sha, ...paths], {
      env: { ...process.env, PRQ_TREE: tree },
      maxBuffer: MAX_BUFFER,
    });
  }
  return { diffFile, bodyFile, tree };
}

const scorerFailure = (scorer: string, error: { stderr?: string; message: string }) =>
  `${scorer}: ${
    String(error.stderr || error.message)
      .trim()
      .split('\n')[0]
  }`;

async function runAudit(pr: PullRequest): Promise<Audit> {
  const headRef = `refs/prq/${pr.number}/head`;
  const baseRef = `refs/prq/${pr.number}/base`;
  await git(
    'fetch',
    '--quiet',
    '--no-tags',
    'origin',
    `+refs/pull/${pr.number}/head:${headRef}`,
    `+refs/heads/${pr.baseRefName}:${baseRef}`,
  );
  const sha = (await git('rev-parse', headRef)).trim();
  const mergeBase = (await git('merge-base', baseRef, sha)).trim();
  const scratch = mkdtempSync(join(tmpdir(), `prq-${pr.number}-`));
  const audit: Audit = { sha, at: new Date().toISOString(), comments: null, scope: null, errors: [] };
  try {
    const { diffFile, bodyFile, tree } = await writeScorerInputs(pr, sha, mergeBase, scratch);
    const score = async (script: string, extra: string[]) =>
      JSON.parse(
        (await run(process.execPath, [script, '--diff', diffFile, '--repo', tree, ...extra], { maxBuffer: MAX_BUFFER }))
          .stdout,
      );
    await Promise.all([
      score(COMMENT_SCORE, [])
        .then((report) => {
          audit.comments = { flagged: report.summary.flagged, total: report.summary.comments };
        })
        .catch((error) => audit.errors.push(scorerFailure('comment-score', error))),
      score(SCOPE_SCORE, ['--body', bodyFile])
        .then((report) => {
          audit.scope = {
            verdict: report.summary.verdict,
            functionsFlagged: report.functions.filter((f: { actions: string[] }) => !f.actions.includes('keep')).length,
          };
        })
        .catch((error) => audit.errors.push(scorerFailure('scope-score', error))),
    ]);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
    await git('update-ref', '-d', headRef).catch(() => {});
    await git('update-ref', '-d', baseRef).catch(() => {});
  }
  if (audit.comments || audit.scope) {
    mkdirSync(auditDir(pr.repository.nameWithOwner), { recursive: true });
    writeFileSync(
      join(auditDir(pr.repository.nameWithOwner), `${pr.number}-${sha}.json`),
      JSON.stringify(audit, null, 2),
    );
  }
  return audit;
}

async function auditMany(prs: PullRequest[], repo: string | null) {
  if (!process.env.TYPESAFE_API_KEY) {
    process.stderr.write('prq: TYPESAFE_API_KEY is not set, so the audits cannot run.\n');
    return;
  }
  const todo = prs.filter((pr) => latestAudit(pr)?.stale !== false);
  const elsewhere = todo.filter((pr) => pr.repository.nameWithOwner !== repo);
  if (elsewhere.length) {
    process.stderr.write(
      `prq: skipping ${elsewhere.length} audit(s) outside ${repo ?? 'a checkout'}; run --audit inside each repository.\n`,
    );
  }
  const queue = todo.filter((pr) => pr.repository.nameWithOwner === repo);
  let done = 0;
  const worker = async () => {
    for (let pr = queue.shift(); pr; pr = queue.shift()) {
      const audit = await runAudit(pr).catch(
        (error): Audit => ({
          sha: '',
          at: '',
          comments: null,
          scope: null,
          errors: [String(error.message).split('\n')[0]],
        }),
      );
      done++;
      const result = audit.errors.length ? `failed: ${audit.errors.join('; ')}` : qualitySentence(audit);
      process.stderr.write(`prq: audited #${pr.number} (${done}/${done + queue.length}) ${result}\n`);
    }
  };
  await Promise.all(Array.from({ length: AUDIT_CONCURRENCY }, worker));
}

const color = process.env.NO_COLOR
  ? () => (s: string) => s
  : (code: string) => (s: string) => `\x1b[${code}m${s}\x1b[0m`;
const c = {
  red: color('31'),
  green: color('32'),
  yellow: color('33'),
  blue: color('34'),
  magenta: color('35'),
  cyan: color('36'),
  dim: color('2'),
  bold: color('1'),
};

const STATE_LABEL: Record<State, string> = {
  you: c.red('you'.padEnd(10)),
  rerequest: c.yellow('re-request'),
  unassigned: c.magenta('unassigned'),
  waiting: c.blue('waiting'.padEnd(10)),
  approved: c.green('approved'.padEnd(10)),
};

function ago(iso: string | null): string {
  if (!iso) {
    return '';
  }
  const s = (Date.now() - Date.parse(iso)) / 1000;
  if (s < 3600) {
    return `${Math.floor(s / 60)}m`;
  }
  if (s < 86400) {
    return `${Math.floor(s / 3600)}h`;
  }
  if (s < 2592000) {
    return `${Math.floor(s / 86400)}d`;
  }
  return `${Math.floor(s / 2592000)}mo`;
}

const visibleLength = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '').length;
const padVisible = (s: string, width: number) => s + ' '.repeat(Math.max(0, width - visibleLength(s)));

function priorityText(a: Assessment): string {
  if (!a.priority) {
    return ' ';
  }
  const text = a.priority.label.charAt(0).toUpperCase();
  return a.priority.rank <= 1 ? c.bold(c.red(text)) : a.priority.rank === 2 ? c.yellow(text) : c.dim(text);
}

const REVIEWER_MARK: Record<Reviewer['status'], (r: Reviewer) => string> = {
  approved: (r) => c.green(`✓${r.name}`),
  changes: (r) => c.red(`✗${r.name}`),
  owed: (r) => c.red(`?${r.name}`),
  rerequest: (r) => c.yellow(`↻${r.name}`),
  pending: (r) => c.dim(`…${r.name}${r.at ? ` ${ago(r.at)}` : ''}`),
};

type FindingLabels = { comments: (n: number) => string; functions: (n: number) => string };

function auditFindings(audit: Audit, labels: FindingLabels): string[] {
  const parts: string[] = [];
  if (audit.comments?.flagged) {
    parts.push(labels.comments(audit.comments.flagged));
  }
  if (audit.scope && audit.scope.verdict !== 'one-problem') {
    parts.push(audit.scope.verdict);
  }
  if (audit.scope?.functionsFlagged) {
    parts.push(labels.functions(audit.scope.functionsFlagged));
  }
  return parts;
}

function qualitySentence(audit: Audit): string {
  const parts = auditFindings(audit, {
    comments: (n) => `${n} comments flagged`,
    functions: (n) => `${n} functions flagged`,
  });
  return parts.length ? parts.join(', ') : 'clean';
}

function qualityMark(audit: Audit, stale: boolean): string {
  const parts = auditFindings(audit, { comments: (n) => `${n}c`, functions: (n) => `${n}f` });
  const mark = `q:${parts.length ? parts.join(',') : 'clean'}`;
  return stale ? c.dim(`${mark}~`) : parts.length ? c.yellow(mark) : c.green(mark);
}

const TITLE_WIDTH = 60;

type Columns = { lead: number; repo: number };

function line(pr: PullRequest, a: Assessment, prefix: string, scope: Options, columns: Columns): string {
  const lead = padVisible(`${prefix}${c.cyan(`#${pr.number}`)}`, columns.lead);
  const fields = [priorityText(a), STATE_LABEL[a.state], lead];
  if (!scope.repo) {
    fields.push(c.dim(pr.repository.nameWithOwner.padEnd(columns.repo)));
  }
  fields.push(pr.isDraft ? c.dim('draft') : '     ');
  const title = pr.title.length > TITLE_WIDTH ? `${pr.title.slice(0, TITLE_WIDTH - 1)}…` : pr.title;
  fields.push(title.padEnd(TITLE_WIDTH));
  const extras = a.reviewers.map((r) => REVIEWER_MARK[r.status](r));
  if (a.peerCommentsSinceMine.length) {
    extras.push(c.red(`+${a.peerCommentsSinceMine.length}💬`));
  }
  if (a.threadsOnYou) {
    extras.push(c.red(`${a.threadsOnYou}⇄`));
  }
  if (a.ci === 'FAILURE' || a.ci === 'ERROR') {
    extras.push(c.red('CI✗'));
  } else if (a.ci === 'PENDING' || a.ci === 'EXPECTED') {
    extras.push(c.dim('CI…'));
  }
  if (a.conflict) {
    extras.push(c.red('conflict'));
  }
  const found = latestAudit(pr);
  if (found) {
    extras.push(qualityMark(found.audit, found.stale));
  }
  return `${fields.join(' ')}  ${extras.join(' ')}`;
}

// One display line per pull request, a header line above each stack, and the
// key and URL after tabs for fzf to act on.
function render(snapshot: Snapshot): { lines: string[]; counts: Map<State, number> } {
  const assessments = new Map(snapshot.prs.map((pr) => [keyOf(pr), assess(pr, snapshot.me)]));
  const counts = new Map<State, number>();
  for (const a of assessments.values()) {
    counts.set(a.state, (counts.get(a.state) ?? 0) + 1);
  }
  const units = orderByUrgency(stacks(snapshot.prs), assessments);
  const columns: Columns = { lead: 0, repo: 0 };
  for (const unit of units) {
    for (const { pr, depth } of unit.members) {
      const prefixLength = unit.members.length > 1 ? 2 * Math.max(0, depth - 1) + 2 : 0;
      columns.lead = Math.max(columns.lead, prefixLength + `#${pr.number}`.length);
      columns.repo = Math.max(columns.repo, pr.repository.nameWithOwner.length);
    }
  }
  const lines: string[] = [];
  for (const unit of units) {
    if (unit.members.length > 1) {
      const approved = unit.members.filter((m) => assessments.get(keyOf(m.pr))!.state === 'approved').length;
      const base = unit.root.baseRefName;
      const onBase = base === unit.root.repository.defaultBranchRef?.name ? '' : c.dim(` on ${base}`);
      lines.push(
        `${c.dim('  stack      ')}${c.bold(`${approved}/${unit.members.length} approved`)}${onBase}\t${keyOf(unit.root)}\t${unit.root.url}`,
      );
    }
    unit.members.forEach(({ pr, depth }, index) => {
      const stacked = unit.members.length > 1;
      const last = index === unit.members.length - 1;
      const branch = index === 0 ? '╭' : last ? '└' : '├';
      const prefix = stacked ? c.dim(`${'  '.repeat(Math.max(0, depth - 1))}${branch} `) : '';
      lines.push(
        `${line(pr, assessments.get(keyOf(pr))!, prefix, snapshot.options, columns)}\t${keyOf(pr)}\t${pr.url}`,
      );
    });
  }
  return { lines, counts };
}

function header(snapshot: Snapshot, counts: Map<State, number>): string {
  const summary = STATES_BY_URGENCY.filter((s) => counts.get(s)).map(
    (s) => `${counts.get(s)} ${STATE_LABEL[s].trim()}`,
  );
  return [
    `${snapshot.prs.length} PR(s): ${summary.join(', ')}. Fetched ${ago(snapshot.fetchedAt)} ago.`,
    'C/H/M/L priority: critical, high, medium, low',
    '✓ approved',
    '✗ changes requested',
    '? owed a reply',
    '↻ needs re-request',
    '… pending',
    '💬 new peer comments',
    '⇄ threads on you',
    'q: audit',
    'enter: open  ctrl-r: re-request ↻  ctrl-a: audit  ctrl-b: agent session  ctrl-l: refetch',
  ].join('\n');
}

function summarySection(pr: PullRequest, a: Assessment): string[] {
  const decision = pr.reviewDecision?.toLowerCase().replace('_', ' ') ?? 'none';
  return [
    c.bold(`#${pr.number} ${pr.title}`),
    `${pr.repository.nameWithOwner}  ${pr.headRefName} → ${pr.baseRefName}`,
    `labels: ${pr.labels.nodes.map((l) => l.name).join(', ') || 'none'}`,
    `state: ${STATE_LABEL[a.state].trim()}${a.reasons.length ? `  (${a.reasons.join('; ')})` : ''}`,
    `CI: ${a.ci?.toLowerCase() ?? 'none'}  mergeable: ${pr.mergeable.toLowerCase()}  decision: ${decision}`,
    `your last comment or push: ${a.lastMineAt ? `${ago(a.lastMineAt)} ago` : 'never'}`,
  ];
}

function stackSection(snapshot: Snapshot, pr: PullRequest): string[] {
  const stack = stacks(snapshot.prs).find((unit) => unit.members.some((m) => m.pr === pr));
  if (!stack || stack.members.length < 2) {
    return [];
  }
  return [
    '',
    c.bold('Stack'),
    ...stack.members.map(({ pr: member, depth }) => {
      const state = STATE_LABEL[assess(member, snapshot.me).state].trim();
      const here = member === pr ? c.bold(' ◀') : '';
      return `  ${'  '.repeat(depth)}#${member.number} ${state} ${member.title.slice(0, 50)}${here}`;
    }),
  ];
}

const REVIEWER_STANDING: Record<Reviewer['status'], string> = {
  approved: 'approved',
  changes: 'requested changes; your reply or push is due',
  owed: 'commented; your reply or push is due',
  rerequest: 'you answered after their review; re-request them',
  pending: 'review requested, pending',
};

function reviewersSection(a: Assessment): string[] {
  return [
    '',
    c.bold('Reviewers'),
    ...(a.reviewers.length ? [] : ['  none requested, none commented']),
    ...a.reviewers.map(
      (r) =>
        `  ${REVIEWER_MARK[r.status](r).padEnd(30)} ${REVIEWER_STANDING[r.status]}${r.at ? `, ${ago(r.at)} ago` : ''}`,
    ),
  ];
}

const PEER_COMMENTS_SHOWN_MAX = 8;
const PEER_COMMENT_CHARS_MAX = 200;

function commentsSection(a: Assessment): string[] {
  return [
    '',
    c.bold(`Peer comments since your last comment or push: ${a.peerCommentsSinceMine.length}`),
    ...a.peerCommentsSinceMine
      .slice(-PEER_COMMENTS_SHOWN_MAX)
      .flatMap((comment) => [
        `  ${c.cyan(comment.author)} ${ago(comment.at)} ago in ${comment.where}`,
        `    ${comment.body.replace(/\s+/g, ' ').trim().slice(0, PEER_COMMENT_CHARS_MAX)}`,
      ]),
    ...(a.threadsOnYou ? [`  ${a.threadsOnYou} unresolved thread(s) end with a peer's comment`] : []),
  ];
}

function qualitySection(pr: PullRequest): string[] {
  const found = latestAudit(pr);
  if (!found) {
    return ['', c.bold('Quality'), '  not audited; ctrl-a audits this head'];
  }
  const { audit, stale } = found;
  const head = stale
    ? `stale, from ${audit.sha.slice(0, 10)} (head is ${pr.headRefOid.slice(0, 10)})`
    : `head ${audit.sha.slice(0, 10)}`;
  const comments = audit.comments ? `${audit.comments.flagged} of ${audit.comments.total} added flagged` : 'not scored';
  const scope = audit.scope
    ? `${audit.scope.verdict}, ${audit.scope.functionsFlagged} function(s) flagged`
    : 'not scored';
  const flagged =
    audit.comments?.flagged || audit.scope?.functionsFlagged || (audit.scope && audit.scope.verdict !== 'one-problem');
  return [
    '',
    c.bold('Quality'),
    `  ${head}, ${ago(audit.at)} ago`,
    `  comments: ${comments}`,
    `  scope: ${scope}`,
    ...audit.errors.map((e) => c.red(`  ${e}`)),
    ...(flagged ? [c.dim('  run the comment-audit and scope-audit skills on the branch for the edits')] : []),
  ];
}

function detail(snapshot: Snapshot, key: string): string {
  const pr = snapshot.prs.find((candidate) => keyOf(candidate) === key);
  if (!pr) {
    return '';
  }
  const a = assess(pr, snapshot.me);
  return [
    ...summarySection(pr, a),
    ...stackSection(snapshot, pr),
    ...reviewersSection(a),
    ...commentsSection(a),
    ...qualitySection(pr),
  ].join('\n');
}

const snapshotPath = () => process.env.PRQ_SNAPSHOT!;
const readSnapshot = (): Snapshot => JSON.parse(readFileSync(snapshotPath(), 'utf8'));
const writeSnapshot = (snapshot: Snapshot) => writeFileSync(snapshotPath(), JSON.stringify(snapshot));

async function rerequest(key: string) {
  const snapshot = readSnapshot();
  const pr = snapshot.prs.find((candidate) => keyOf(candidate) === key);
  if (!pr) {
    return;
  }
  const names = assess(pr, snapshot.me)
    .reviewers.filter((r) => r.status === 'rerequest')
    .map((r) => r.name);
  if (!names.length) {
    process.stderr.write(`#${pr.number} has no reviewer to re-request.\n`);
    return;
  }
  await gh('pr', 'edit', String(pr.number), '--repo', pr.repository.nameWithOwner, '--add-reviewer', names.join(','));
  // Mirror the request locally so the list redraws without a refetch.
  const now = new Date().toISOString();
  for (const login of names) {
    pr.reviewRequests.nodes.push({ requestedReviewer: { __typename: 'User', login } });
    pr.timelineItems.nodes.push({
      __typename: 'ReviewRequestedEvent',
      createdAt: now,
      requestedReviewer: { __typename: 'User', login },
    });
  }
  writeSnapshot(snapshot);
}

function fzf(snapshot: Snapshot, lines: string[], counts: Map<State, number>) {
  const self = `'${process.execPath}' '${process.argv[1]}'`;
  const child = spawn(
    'fzf',
    [
      '--ansi',
      '--no-sort',
      '--layout=reverse',
      '--delimiter=\t',
      '--with-nth=1',
      `--header=${header(snapshot, counts)}`,
      '--header-first',
      `--preview=${self} --detail {2}`,
      '--preview-window=right:30%:wrap',
      '--bind=enter:execute-silent(open {3})',
      `--bind=ctrl-r:execute(${self} --rerequest {2})+reload(${self} --lines)+refresh-preview`,
      `--bind=ctrl-a:execute(${self} --audit-one {2})+reload(${self} --lines)+refresh-preview`,
      `--bind=ctrl-b:execute(${self} --session {2})`,
      `--bind=ctrl-l:reload(${self} --refetch)+refresh-preview`,
    ],
    { stdio: ['pipe', 'inherit', 'inherit'], env: { ...process.env, PRQ_SNAPSHOT: snapshotPath() } },
  );
  child.stdin.end(`${lines.join('\n')}\n`);
  child.on('exit', () => rmSync(snapshotPath(), { force: true }));
}

type Values = {
  all: boolean;
  drafts: boolean;
  audit: boolean;
  plain: boolean;
  help: boolean;
  detail?: string;
  rerequest?: string;
  'audit-one'?: string;
  session?: string;
  lines: boolean;
  refetch: boolean;
};

// The fzf bindings call back with PRQ_SNAPSHOT set and act on that snapshot.
async function runCallback(values: Values): Promise<boolean> {
  if (values.detail) {
    process.stdout.write(`${detail(readSnapshot(), values.detail)}\n`);
  } else if (values.rerequest) {
    await rerequest(values.rerequest);
  } else if (values.session) {
    const snapshot = readSnapshot();
    const pr = snapshot.prs.find((candidate) => keyOf(candidate) === values.session);
    if (pr) {
      const text = brief(pr, assess(pr, snapshot.me), snapshot.me, latestAudit(pr)?.audit ?? null);
      await startSession(pr.repository.nameWithOwner, pr.headRefName, text);
    }
  } else if (values['audit-one']) {
    const pr = readSnapshot().prs.find((candidate) => keyOf(candidate) === values['audit-one']);
    await auditMany(pr ? [pr] : [], await currentRepo());
  } else if (values.lines || values.refetch) {
    let snapshot = readSnapshot();
    if (values.refetch) {
      snapshot = await fetchSnapshot(snapshot.options);
      writeSnapshot(snapshot);
    }
    process.stdout.write(`${render(snapshot).lines.join('\n')}\n`);
  } else {
    return false;
  }
  return true;
}

async function main() {
  const { values } = parseArgs({
    options: {
      all: { type: 'boolean', default: false },
      drafts: { type: 'boolean', default: false },
      audit: { type: 'boolean', default: false },
      plain: { type: 'boolean', default: false },
      help: { type: 'boolean', short: 'h', default: false },
      detail: { type: 'string' },
      rerequest: { type: 'string' },
      'audit-one': { type: 'string' },
      session: { type: 'string' },
      lines: { type: 'boolean', default: false },
      refetch: { type: 'boolean', default: false },
    },
  });
  if (values.help) {
    return void process.stdout.write(`${USAGE}\n`);
  }
  if (await runCallback(values)) {
    return;
  }

  const repo = await currentRepo();
  if (!values.all && !repo) {
    process.stderr.write('No GitHub repository here. Run prq inside one, or pass --all.\n');
    process.exit(1);
  }
  const snapshot = await fetchSnapshot({ all: values.all, drafts: values.drafts, repo: values.all ? null : repo });
  if (!snapshot.prs.length) {
    return void process.stdout.write('No open pull requests.\n');
  }
  if (values.audit) {
    await auditMany(snapshot.prs, repo);
  }

  const { lines, counts } = render(snapshot);
  if (values.plain || !process.stdout.isTTY) {
    process.stdout.write(`${header(snapshot, counts).split('\n').slice(0, -1).join('\n')}\n\n`);
    process.stdout.write(`${lines.map((l) => l.split('\t')[0]).join('\n')}\n`);
    return;
  }
  process.env.PRQ_SNAPSHOT = join(mkdtempSync(join(tmpdir(), 'prq-')), 'snapshot.json');
  writeSnapshot(snapshot);
  fzf(snapshot, lines, counts);
}

await main();
