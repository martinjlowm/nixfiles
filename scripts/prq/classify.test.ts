import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { assess, keyOf, orderByUrgency, type PullRequest, priorityOf, stacks } from './classify.ts';

const me = 'me';
const user = (login: string) => ({ login, __typename: 'User' });
const bot = (login: string) => ({ login, __typename: 'Bot' });

function pr(overrides: Partial<PullRequest> & { number?: number } = {}): PullRequest {
  return {
    number: 1,
    title: 't',
    url: 'u',
    isDraft: false,
    body: '',
    createdAt: '2026-01-01T00:00:00Z',
    baseRefName: 'master',
    headRefName: 'feature',
    headRefOid: 'sha',
    mergeable: 'MERGEABLE',
    reviewDecision: 'REVIEW_REQUIRED',
    repository: { nameWithOwner: 'o/r', defaultBranchRef: { name: 'master' } },
    labels: { nodes: [] },
    reviewRequests: { nodes: [] },
    reviews: { nodes: [] },
    comments: { nodes: [] },
    reviewThreads: { nodes: [] },
    commits: { nodes: [{ commit: { committedDate: '2026-01-01T00:00:00Z', statusCheckRollup: null } }] },
    timelineItems: { nodes: [] },
    ...overrides,
  };
}

const review = (author: ReturnType<typeof user>, state: string, submittedAt: string, body = '') => ({
  author,
  state,
  submittedAt,
  body,
});

describe('assess', () => {
  it('is unassigned with no request and no review', () => {
    assert.equal(assess(pr(), me).state, 'unassigned');
  });

  it('waits on a pending request', () => {
    const a = assess(
      pr({ reviewRequests: { nodes: [{ requestedReviewer: { __typename: 'User', login: 'ann' } }] } }),
      me,
    );
    assert.equal(a.state, 'waiting');
    assert.deepEqual(
      a.reviewers.map((r) => [r.name, r.status]),
      [['ann', 'pending']],
    );
  });

  it('puts a comment newer than your last push on you', () => {
    const a = assess(
      pr({ reviews: { nodes: [review(user('ann'), 'COMMENTED', '2026-01-02T00:00:00Z', 'why?')] } }),
      me,
    );
    assert.equal(a.state, 'you');
    assert.equal(a.reviewers[0].status, 'owed');
    assert.equal(a.peerCommentsSinceMine.length, 1);
  });

  it('asks for a re-request once you pushed after their review', () => {
    const a = assess(
      pr({
        reviews: { nodes: [review(user('ann'), 'CHANGES_REQUESTED', '2026-01-02T00:00:00Z', 'fix it')] },
        commits: { nodes: [{ commit: { committedDate: '2026-01-03T00:00:00Z', statusCheckRollup: null } }] },
      }),
      me,
    );
    assert.equal(a.state, 'rerequest');
    assert.equal(a.reviewers[0].status, 'rerequest');
  });

  it('counts your thread reply as an answer', () => {
    const a = assess(
      pr({
        reviews: { nodes: [review(user('ann'), 'COMMENTED', '2026-01-02T00:00:00Z')] },
        reviewThreads: {
          nodes: [
            {
              isResolved: false,
              path: 'a.ts',
              comments: {
                nodes: [
                  { author: user('ann'), createdAt: '2026-01-02T00:00:00Z', body: 'q', url: '' },
                  { author: user(me), createdAt: '2026-01-04T00:00:00Z', body: 'a', url: '' },
                ],
              },
            },
          ],
        },
      }),
      me,
    );
    assert.equal(a.threadsOnYou, 0);
    assert.equal(a.state, 'rerequest');
  });

  it('ignores bots on every count', () => {
    const a = assess(
      pr({
        reviews: { nodes: [review(bot('claude'), 'COMMENTED', '2026-01-02T00:00:00Z', 'nit')] },
        comments: { nodes: [{ author: null, createdAt: '2026-01-02T00:00:00Z', body: 'x', url: '' }] },
      }),
      me,
    );
    assert.equal(a.state, 'unassigned');
    assert.equal(a.peerCommentsSinceMine.length, 0);
  });

  it('keeps a pending re-request pending', () => {
    const a = assess(
      pr({
        reviews: { nodes: [review(user('ann'), 'COMMENTED', '2026-01-02T00:00:00Z')] },
        reviewRequests: { nodes: [{ requestedReviewer: { __typename: 'User', login: 'ann' } }] },
        commits: { nodes: [{ commit: { committedDate: '2026-01-03T00:00:00Z', statusCheckRollup: null } }] },
      }),
      me,
    );
    assert.equal(a.state, 'waiting');
  });

  it('treats an approval on a stacked pull request as approved', () => {
    const a = assess(
      pr({
        reviewDecision: null,
        reviews: { nodes: [review(user('ann'), 'APPROVED', '2026-01-02T00:00:00Z', 'lgtm')] },
      }),
      me,
    );
    assert.equal(a.state, 'approved');
    assert.equal(a.peerCommentsSinceMine.length, 0);
  });

  it('leaves CI and conflicts out of the state', () => {
    const a = assess(
      pr({
        mergeable: 'CONFLICTING',
        commits: {
          nodes: [{ commit: { committedDate: '2026-01-01T00:00:00Z', statusCheckRollup: { state: 'FAILURE' } } }],
        },
      }),
      me,
    );
    assert.equal(a.state, 'unassigned');
    assert.equal(a.conflict, true);
    assert.equal(a.ci, 'FAILURE');
  });
});

describe('priorityOf', () => {
  it('reads the highest priority label', () => {
    assert.deepEqual(priorityOf(['Security', 'priority: medium', 'Priority: High']), { label: 'high', rank: 1 });
    assert.equal(priorityOf(['bug']), null);
  });
});

describe('stacks', () => {
  it('chains pull requests by base branch and orders by urgency', () => {
    const bottom = pr({ number: 1, headRefName: 'a' });
    const top = pr({ number: 2, headRefName: 'b', baseRefName: 'a' });
    const alone = pr({
      number: 3,
      headRefName: 'c',
      labels: { nodes: [{ name: 'priority: high' }] },
      reviewRequests: { nodes: [{ requestedReviewer: { __typename: 'User', login: 'ann' } }] },
    });
    const units = stacks([top, alone, bottom]);
    assert.deepEqual(
      units.map((u) => u.members.map((m) => [m.pr.number, m.depth])),
      [
        [[3, 0]],
        [
          [1, 0],
          [2, 1],
        ],
      ],
    );
    const assessments = new Map([top, alone, bottom].map((p) => [keyOf(p), assess(p, me)]));
    assert.deepEqual(
      orderByUrgency(units, assessments).map((u) => u.root.number),
      [1, 3],
    );
  });
});
