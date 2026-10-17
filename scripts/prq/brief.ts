// Writes the prompt a new agent session starts from: what the conversation on
// one pull request asks of its author, with links, so the session can address
// it without anyone posting a request on the pull request.
import type { Assessment, PullRequest } from './classify.ts';

export type AuditSummary = {
  sha: string;
  comments: { flagged: number; total: number } | null;
  scope: { verdict: string; functionsFlagged: number } | null;
};

const BODY_CHARS_MAX = 1500;
const quote = (text: string) =>
  text
    .trim()
    .slice(0, BODY_CHARS_MAX)
    .split('\n')
    .map((line) => `> ${line}`)
    .join('\n');

function openThreads(pr: PullRequest, me: string): string[] {
  return pr.reviewThreads.nodes
    .filter((thread) => !thread.isResolved && thread.comments.nodes.length > 0)
    .map((thread) => {
      const last = thread.comments.nodes.at(-1)!;
      const waiting = last.author?.login !== me && last.author?.__typename === 'User';
      return [
        `- \`${thread.path}\`, ${waiting ? `last word from ${last.author!.login}` : 'last word yours'}: ${last.url}`,
        quote(last.body)
          .split('\n')
          .map((line) => `  ${line}`)
          .join('\n'),
      ].join('\n');
    });
}

function qualityLines(audit: AuditSummary | null, headRefOid: string): string[] {
  if (!audit || audit.sha !== headRefOid) {
    return [];
  }
  const lines: string[] = [];
  if (audit.comments?.flagged) {
    lines.push(`- The comment audit flags ${audit.comments.flagged} of ${audit.comments.total} added comment blocks.`);
  }
  if (audit.scope && audit.scope.verdict !== 'one-problem') {
    lines.push(`- The scope audit's verdict is \`${audit.scope.verdict}\`.`);
  }
  if (audit.scope?.functionsFlagged) {
    lines.push(`- The scope audit flags ${audit.scope.functionsFlagged} function(s).`);
  }
  return lines;
}

export function brief(pr: PullRequest, a: Assessment, me: string, audit: AuditSummary | null): string {
  const reviewers = a.reviewers.map(
    (r) => `- ${r.name}: ${r.status}${r.verdict ? ` (${r.verdict.toLowerCase()})` : ''}`,
  );
  const comments = a.peerCommentsSinceMine.map(
    (comment) => `- ${comment.author} in ${comment.where}: ${comment.url}\n${quote(comment.body)}`,
  );
  const threads = openThreads(pr, me);
  const quality = qualityLines(audit, pr.headRefOid);
  const ci = a.ci === 'FAILURE' || a.ci === 'ERROR' ? ['- CI fails on the head commit.'] : [];
  const conflict = a.conflict ? [`- The branch conflicts with \`${pr.baseRefName}\`.`] : [];
  const section = (title: string, lines: string[]) => (lines.length ? [`## ${title}`, '', ...lines, ''] : []);

  return [
    `Address what is open on ${pr.repository.nameWithOwner}#${pr.number}, "${pr.title}" (${pr.url}),`,
    `branch \`${pr.headRefName}\` onto \`${pr.baseRefName}\`. Work on that branch.`,
    '',
    `prq classifies it as \`${a.state}\`${a.reasons.length ? `: ${a.reasons.join('; ')}` : ''}.`,
    '',
    ...section('Reviewers', reviewers),
    ...section('Comments since my last comment or push', comments),
    ...section('Unresolved review threads', threads),
    ...section('Checks', [...ci, ...conflict, ...quality]),
    'Read the full conversation first with `agent-pr-digest`, since this list quotes only the',
    'last comment of each thread. Then follow the `pr-comments` skill for the threads, and the',
    '`comment-audit` and `scope-audit` skills for the audit findings. Re-requesting reviews stays',
    'with me.',
  ].join('\n');
}
