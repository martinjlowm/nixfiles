// Decides, for each of your open pull requests, who holds the ball: you, a
// reviewer who needs asking again, a reviewer still pending, or nobody yet.
// Pure functions over the GraphQL shape that prq.ts fetches.

export type Actor = { login: string; __typename: string } | null;

export type PullRequest = {
  number: number;
  title: string;
  url: string;
  isDraft: boolean;
  body: string;
  createdAt: string;
  baseRefName: string;
  headRefName: string;
  headRefOid: string;
  mergeable: 'MERGEABLE' | 'CONFLICTING' | 'UNKNOWN';
  reviewDecision: 'APPROVED' | 'CHANGES_REQUESTED' | 'REVIEW_REQUIRED' | null;
  repository: { nameWithOwner: string; defaultBranchRef: { name: string } | null };
  labels: { nodes: { name: string }[] };
  reviewRequests: { nodes: { requestedReviewer: { __typename: string; login?: string; slug?: string } | null }[] };
  reviews: { nodes: { author: Actor; state: string; submittedAt: string | null; body: string }[] };
  comments: { nodes: { author: Actor; createdAt: string; body: string; url: string }[] };
  reviewThreads: {
    nodes: {
      isResolved: boolean;
      path: string;
      comments: { nodes: { author: Actor; createdAt: string; body: string; url: string }[] };
    }[];
  };
  commits: { nodes: { commit: { committedDate: string; statusCheckRollup: { state: string } | null } }[] };
  timelineItems: {
    nodes: (
      | {
          __typename: 'ReviewRequestedEvent';
          createdAt: string;
          requestedReviewer: { __typename: string; login?: string; slug?: string } | null;
        }
      | { __typename: 'HeadRefForcePushedEvent'; createdAt: string }
    )[];
  };
};

export const STATES_BY_URGENCY = ['you', 'rerequest', 'unassigned', 'waiting', 'approved'] as const;
export type State = (typeof STATES_BY_URGENCY)[number];

// `owed`: they spoke after your last comment or push, so a reply or a push is
// yours to make. `rerequest`: you answered them, and GitHub dropped their
// request when they reviewed, so nothing tells them to look again.
export type ReviewerStatus = 'approved' | 'changes' | 'owed' | 'rerequest' | 'pending';

export type Reviewer = {
  name: string;
  team: boolean;
  status: ReviewerStatus;
  // Their newest review or comment, or for a pending request, when you asked.
  at: string | null;
  verdict: 'APPROVED' | 'CHANGES_REQUESTED' | null;
};

export type PeerComment = { author: string; at: string; body: string; url: string; where: string };

export type Assessment = {
  key: string;
  state: State;
  reasons: string[];
  priority: { label: string; rank: number } | null;
  reviewers: Reviewer[];
  lastMineAt: string | null;
  peerCommentsSinceMine: PeerComment[];
  threadsOnYou: number;
  ci: string | null;
  conflict: boolean;
};

export const keyOf = (pr: Pick<PullRequest, 'repository' | 'number'>) => `${pr.repository.nameWithOwner}#${pr.number}`;

const PRIORITY_RANK: Record<string, number> = { critical: 0, urgent: 0, highest: 0, high: 1, medium: 2, low: 3 };

export function priorityOf(labels: string[]): Assessment['priority'] {
  const found = labels
    .map((label) => /^priority\s*:\s*(.+)$/i.exec(label.trim()))
    .filter((match): match is RegExpExecArray => match !== null)
    .map((match) => ({
      label: match[1].trim().toLowerCase(),
      rank: PRIORITY_RANK[match[1].trim().toLowerCase()] ?? 4,
    }));
  return found.sort((a, b) => a.rank - b.rank)[0] ?? null;
}

// A deleted account reports a null author and counts as a bot, like every
// account GitHub types as one (botler, claude, advanced security).
function isPeer(author: Actor, me: string): author is { login: string; __typename: string } {
  return author !== null && author.__typename === 'User' && author.login !== me;
}

const latest = (...dates: (string | null | undefined)[]) =>
  dates
    .filter((date): date is string => !!date)
    .sort()
    .at(-1) ?? null;

type ThreadComment = PullRequest['reviewThreads']['nodes'][number]['comments']['nodes'][number] & { where: string };
type Verdict = { state: 'APPROVED' | 'CHANGES_REQUESTED'; at: string } | null;

const threadCommentsOf = (pr: PullRequest): ThreadComment[] =>
  pr.reviewThreads.nodes.flatMap((thread) =>
    thread.comments.nodes.map((comment) => ({ ...comment, where: thread.path })),
  );

function lastMineAtOf(pr: PullRequest, threadComments: ThreadComment[], me: string): string | null {
  const mine = (author: Actor) => author?.login === me;
  return latest(
    pr.commits.nodes[0]?.commit.committedDate,
    ...pr.timelineItems.nodes
      .filter((item) => item.__typename === 'HeadRefForcePushedEvent')
      .map((item) => item.createdAt),
    ...pr.comments.nodes.filter((c) => mine(c.author)).map((c) => c.createdAt),
    ...pr.reviews.nodes.filter((r) => mine(r.author)).map((r) => r.submittedAt),
    ...threadComments.filter((c) => mine(c.author)).map((c) => c.createdAt),
  );
}

// A review that only wraps inline comments carries an empty body; its thread
// comments are counted on their own, so only a review with a body counts here.
// An approval's body asks nothing of you.
function peerCommentsOf(pr: PullRequest, threadComments: ThreadComment[], me: string): PeerComment[] {
  return [
    ...pr.comments.nodes
      .filter((c) => isPeer(c.author, me))
      .map((c) => ({ author: c.author!.login, at: c.createdAt, body: c.body, url: c.url, where: 'conversation' })),
    ...threadComments
      .filter((c) => isPeer(c.author, me))
      .map((c) => ({ author: c.author!.login, at: c.createdAt, body: c.body, url: c.url, where: c.where })),
    ...pr.reviews.nodes
      .filter(
        (r) =>
          isPeer(r.author, me) && r.submittedAt && r.body.trim() && r.state !== 'PENDING' && r.state !== 'APPROVED',
      )
      .map((r) => ({
        author: r.author!.login,
        at: r.submittedAt!,
        body: `[${r.state.toLowerCase().replace('_', ' ')}] ${r.body}`,
        url: pr.url,
        where: 'review',
      })),
  ].sort((a, b) => a.at.localeCompare(b.at));
}

const threadsEndingWithPeer = (pr: PullRequest, me: string) =>
  pr.reviewThreads.nodes.filter((thread) => {
    const last = thread.comments.nodes.at(-1);
    return !thread.isResolved && last && isPeer(last.author, me);
  }).length;

const reviewerName = (reviewer: { login?: string; slug?: string }) => reviewer.login ?? `@${reviewer.slug}`;

function requestTimes(pr: PullRequest): Map<string, string> {
  const requestedAt = new Map<string, string>();
  for (const item of pr.timelineItems.nodes) {
    if (item.__typename === 'ReviewRequestedEvent' && item.requestedReviewer) {
      const name = reviewerName(item.requestedReviewer);
      requestedAt.set(name, latest(requestedAt.get(name), item.createdAt)!);
    }
  }
  return requestedAt;
}

function isTeamByPendingReviewer(pr: PullRequest, me: string): Map<string, boolean> {
  const pending = new Map<string, boolean>();
  for (const { requestedReviewer } of pr.reviewRequests.nodes) {
    if (requestedReviewer?.__typename === 'Team') {
      pending.set(reviewerName(requestedReviewer), true);
    } else if (requestedReviewer?.__typename === 'User' && requestedReviewer.login !== me) {
      pending.set(reviewerName(requestedReviewer), false);
    }
  }
  return pending;
}

const nextVerdict = (current: Verdict, review: PullRequest['reviews']['nodes'][number]): Verdict => {
  const at = review.submittedAt!;
  if ((review.state === 'APPROVED' || review.state === 'CHANGES_REQUESTED') && (!current || at > current.at)) {
    return { state: review.state, at };
  }
  return review.state === 'DISMISSED' && current && at >= current.at ? null : current;
};

function peerVerdicts(pr: PullRequest, me: string): Map<string, Verdict> {
  const verdicts = new Map<string, Verdict>();
  for (const review of pr.reviews.nodes) {
    if (isPeer(review.author, me) && review.submittedAt && review.state !== 'PENDING') {
      verdicts.set(review.author.login, nextVerdict(verdicts.get(review.author.login) ?? null, review));
    }
  }
  return verdicts;
}

function lastSpokeAtOf(pr: PullRequest, peerComments: PeerComment[], me: string): Map<string, string> {
  const spokeAt = new Map<string, string>();
  const note = (name: string, at: string) => spokeAt.set(name, latest(spokeAt.get(name), at)!);
  for (const review of pr.reviews.nodes) {
    if (isPeer(review.author, me) && review.submittedAt && review.state !== 'PENDING') {
      note(review.author.login, review.submittedAt);
    }
  }
  for (const comment of peerComments) {
    note(comment.author, comment.at);
  }
  return spokeAt;
}

function standing(
  pending: boolean,
  verdict: Reviewer['verdict'],
  spokeAt: string | null,
  lastMineAt: string | null,
): ReviewerStatus {
  if (pending) {
    return 'pending';
  }
  if (verdict === 'APPROVED') {
    return 'approved';
  }
  if (spokeAt && lastMineAt && lastMineAt > spokeAt) {
    return 'rerequest';
  }
  return verdict === 'CHANGES_REQUESTED' ? 'changes' : 'owed';
}

const STATUS_ORDER: ReviewerStatus[] = ['changes', 'owed', 'rerequest', 'pending', 'approved'];

function reviewersOf(pr: PullRequest, peerComments: PeerComment[], lastMineAt: string | null, me: string): Reviewer[] {
  const pending = isTeamByPendingReviewer(pr, me);
  const requestedAt = requestTimes(pr);
  const verdicts = peerVerdicts(pr, me);
  const spokeAt = lastSpokeAtOf(pr, peerComments, me);
  const names = new Set([...pending.keys(), ...spokeAt.keys()]);
  return [...names]
    .map((name) => {
      const verdict = verdicts.get(name)?.state ?? null;
      const status = standing(pending.has(name), verdict, spokeAt.get(name) ?? null, lastMineAt);
      const at = status === 'pending' ? requestedAt.get(name) : spokeAt.get(name);
      return { name, team: pending.get(name) === true, status, verdict, at: at ?? null };
    })
    .sort((a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status) || a.name.localeCompare(b.name));
}

// A pull request stacked on another branch has no decision of its own, so an
// approval without a standing change request stands in for one.
const isApproved = (pr: PullRequest, reviewers: Reviewer[]) =>
  pr.reviewDecision === 'APPROVED' ||
  (pr.reviewDecision === null &&
    reviewers.some((r) => r.verdict === 'APPROVED') &&
    !reviewers.some((r) => r.verdict === 'CHANGES_REQUESTED'));

const plural = (count: number, noun: string) => `${count} ${noun}${count > 1 ? 's' : ''}`;
const names = (reviewers: Reviewer[]) => reviewers.map((r) => r.name).join(', ');

// CI and conflicts stay out of the state: they rot on every idle pull request
// as the base moves, and would bury the review conversation.
function stateOf(
  approved: boolean,
  reviewers: Reviewer[],
  peerCommentsSinceMine: PeerComment[],
  threadsOnYou: number,
): { state: State; reasons: string[] } {
  const reasons: string[] = [];
  const owing = reviewers.filter((r) => r.status === 'changes' || r.status === 'owed');
  if (owing.length) {
    reasons.push(`reply to ${names(owing)}`);
  }
  if (threadsOnYou) {
    reasons.push(`${plural(threadsOnYou, 'thread')} on you`);
  }
  const unanswered = peerCommentsSinceMine.filter((comment) => !owing.some((r) => r.name === comment.author));
  if (unanswered.length) {
    reasons.push(`${plural(unanswered.length, 'new comment')}`);
  }
  if (reasons.length) {
    return { state: 'you', reasons };
  }
  if (approved) {
    return { state: 'approved', reasons };
  }
  const rerequest = reviewers.filter((r) => r.status === 'rerequest');
  if (rerequest.length) {
    return { state: 'rerequest', reasons: [`re-request ${names(rerequest)}`] };
  }
  if (reviewers.some((r) => r.status === 'pending')) {
    return { state: 'waiting', reasons };
  }
  return { state: 'unassigned', reasons: ['no reviewer requested'] };
}

export function assess(pr: PullRequest, me: string): Assessment {
  const threadComments = threadCommentsOf(pr);
  const lastMineAt = lastMineAtOf(pr, threadComments, me);
  const peerComments = peerCommentsOf(pr, threadComments, me);
  const peerCommentsSinceMine = peerComments.filter((c) => !lastMineAt || c.at > lastMineAt);
  const threadsOnYou = threadsEndingWithPeer(pr, me);
  const reviewers = reviewersOf(pr, peerComments, lastMineAt, me);
  return {
    key: keyOf(pr),
    ...stateOf(isApproved(pr, reviewers), reviewers, peerCommentsSinceMine, threadsOnYou),
    priority: priorityOf(pr.labels.nodes.map((l) => l.name)),
    reviewers,
    lastMineAt,
    peerCommentsSinceMine,
    threadsOnYou,
    ci: pr.commits.nodes[0]?.commit.statusCheckRollup?.state ?? null,
    conflict: pr.mergeable === 'CONFLICTING',
  };
}

export type Unit = { root: PullRequest; members: { pr: PullRequest; depth: number }[] };

// Groups pull requests into stacks by following each one's base branch to the
// head branch of another listed pull request. A pull request whose base no
// listed pull request owns is a root, so a stack whose lower layers merged or
// are filtered out still lists from its lowest open layer.
export function stacks(prs: PullRequest[]): Unit[] {
  const byHead = new Map(prs.map((pr) => [`${pr.repository.nameWithOwner}:${pr.headRefName}`, pr]));
  const children = new Map<string, PullRequest[]>();
  const roots: PullRequest[] = [];
  for (const pr of prs) {
    const parent = byHead.get(`${pr.repository.nameWithOwner}:${pr.baseRefName}`);
    if (parent && parent !== pr) {
      const key = keyOf(parent);
      children.set(key, [...(children.get(key) ?? []), pr]);
    } else {
      roots.push(pr);
    }
  }
  return roots.map((root) => {
    const members: Unit['members'] = [];
    const walk = (pr: PullRequest, depth: number) => {
      members.push({ pr, depth });
      for (const child of (children.get(keyOf(pr)) ?? []).sort((a, b) => a.number - b.number)) {
        walk(child, depth + 1);
      }
    };
    walk(root, 0);
    return { root, members };
  });
}

export function orderByUrgency(units: Unit[], assessments: Map<string, Assessment>): Unit[] {
  const rank = (unit: Unit) => {
    const all = unit.members.map((m) => assessments.get(keyOf(m.pr))!);
    return [
      Math.min(...all.map((a) => STATES_BY_URGENCY.indexOf(a.state))),
      Math.min(...all.map((a) => a.priority?.rank ?? 5)),
      unit.root.createdAt,
    ] as const;
  };
  return [...units].sort((a, b) => {
    const [sa, pa, ca] = rank(a);
    const [sb, pb, cb] = rank(b);
    return sa - sb || pa - pb || ca.localeCompare(cb);
  });
}
