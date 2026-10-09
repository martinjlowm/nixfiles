import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  addedLines,
  commentBlocks,
  historyMarkers,
  lineCommentColumn,
  linesGoverned,
  type Signals,
  syntaxFor,
  verdict,
} from './comments.ts';

const quiet: Signals = {
  restates: 0.1,
  history: 0.1,
  alternative: 0.1,
  intoCode: 0.1,
  duplicate: null,
  value: { score: 1.9, confidence: 0.9 },
  historyMarkers: [],
};

describe('addedLines', () => {
  it('numbers added lines on the new side across hunks and files', () => {
    const diff = [
      'diff --git a/src/a.rs b/src/a.rs',
      '--- a/src/a.rs',
      '+++ b/src/a.rs',
      '@@ -1,2 +1,3 @@',
      ' fn a() {}',
      '+// added',
      ' fn b() {}',
      '@@ -10,0 +11,2 @@',
      '+x',
      '+y',
      'diff --git a/gone.ts b/gone.ts',
      '--- a/gone.ts',
      '+++ /dev/null',
      '@@ -1 +0,0 @@',
      '-z',
    ].join('\n');
    const added = addedLines(diff);
    assert.deepEqual([...added.get('src/a.rs')!], [2, 11, 12]);
    assert.equal(added.has('gone.ts'), false);
  });
});

describe('lineCommentColumn', () => {
  it('ignores markers inside string literals', () => {
    const slash = syntaxFor('a.ts')!;
    assert.equal(lineCommentColumn(`const url = "https://x"; // note`, slash), 25);
    assert.equal(lineCommentColumn(`const url = 'https://x';`, slash), -1);
  });

  it('treats a Rust single quote as a lifetime, not a string', () => {
    assert.equal(lineCommentColumn(`fn f<'a>(x: &'a str) {} // note`, syntaxFor('a.rs')!), 24);
  });
});

describe('commentBlocks', () => {
  it('joins consecutive own-line comments and splits trailing ones', () => {
    const source = [
      '/// Builds the thing.',
      '///',
      '/// Second paragraph.',
      'pub fn build() {',
      '    let x = 1; // trailing',
      '}',
    ].join('\n');
    const blocks = commentBlocks('lib.rs', source);
    assert.equal(blocks.length, 2);
    assert.deepEqual(
      { start: blocks[0].startLine, end: blocks[0].endLine, text: blocks[0].text },
      { start: 1, end: 3, text: 'Builds the thing.\n\nSecond paragraph.' },
    );
    assert.equal(blocks[1].placement, 'trailing');
    assert.equal(blocks[1].text, 'trailing');
  });

  it('reads JSDoc block comments without their stars', () => {
    const source = ['/**', ' * Resolves the tenant.', ' */', 'export function resolve() {}'].join('\n');
    assert.equal(commentBlocks('a.ts', source)[0].text, 'Resolves the tenant.');
  });

  it('skips tool directives and shebangs', () => {
    const source = ['#!/usr/bin/env bash', '# shellcheck disable=SC2086', 'echo $x'].join('\n');
    assert.deepEqual(commentBlocks('run.sh', source), []);
    const ts = ['// biome-ignore lint/style: generated', 'let a = 1;'].join('\n');
    assert.deepEqual(commentBlocks('a.ts', ts), []);
  });

  it('reads hash comments in Nix', () => {
    const source = ['{', '  # The store path the fleet image copies.', '  src = ./.;', '}'].join('\n');
    assert.equal(commentBlocks('default.nix', source)[0].text, 'The store path the fleet image copies.');
  });

  it('returns nothing for an unknown extension', () => {
    assert.deepEqual(commentBlocks('notes.md', '// not code'), []);
  });
});

describe('linesGoverned', () => {
  it('counts code lines up to the next blank line', () => {
    const source = ['// Doc.', 'fn a() {', '    1', '}', '', 'fn b() {}'].join('\n');
    const [block] = commentBlocks('a.rs', source);
    assert.equal(linesGoverned(source, block, syntaxFor('a.rs')!), 3);
  });
});

describe('historyMarkers', () => {
  it('finds references and past-tense narration', () => {
    assert.deepEqual(historyMarkers('The #21471 traversal.'), ['issue or PR number']);
    assert.deepEqual(historyMarkers('Without the header f-f6edf616 used.'), ['finding or ticket id']);
    assert.deepEqual(historyMarkers('QoS 1 as the legacy reactor did.'), ['the past']);
    assert.deepEqual(historyMarkers('Retry once: the broker drops the first publish.'), []);
  });
});

describe('verdict', () => {
  it('keeps a comment with no signal', () => {
    assert.deepEqual(verdict(quiet, { commentLines: 2, codeLines: 4 }), { actions: ['keep'], uncertain: [] });
  });

  it('removes a restatement and drops the weaker trim', () => {
    const signals = { ...quiet, restates: 0.9, alternative: 0.9 };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 1 }).actions, ['remove']);
  });

  it('removes a comment whose deletion costs nothing', () => {
    const signals = { ...quiet, value: { score: 0.3, confidence: 0.8 } };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 1 }).actions, ['remove']);
  });

  it('moves history out on a marker plus a weak Noul', () => {
    const signals = { ...quiet, history: 0.5, historyMarkers: ['issue or PR number'] };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 3 }), {
      actions: ['move-to-commit'],
      uncertain: [],
    });
  });

  it('leaves a mid-range Noul to the reader', () => {
    const signals = { ...quiet, intoCode: 0.5 };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 3 }), {
      actions: ['keep'],
      uncertain: ['intoCode'],
    });
  });

  it('flags a history marker on a kept comment for the reader', () => {
    const signals = { ...quiet, historyMarkers: ['the past'] };
    assert.deepEqual(verdict(signals, { commentLines: 2, codeLines: 5 }), {
      actions: ['keep'],
      uncertain: ['history'],
    });
  });

  it('reports no uncertainty once a Noul already decided the change', () => {
    const signals = { ...quiet, restates: 0.9, intoCode: 0.5, value: { score: 0.3, confidence: 0.2 } };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 1 }), { actions: ['remove'], uncertain: [] });
  });

  it('marks a removal resting only on an unsure value Score', () => {
    const signals = { ...quiet, value: { score: 0.5, confidence: 0.2 } };
    assert.deepEqual(verdict(signals, { commentLines: 1, codeLines: 1 }), {
      actions: ['remove'],
      uncertain: ['value'],
    });
  });

  it('trims a comment longer than the code it governs', () => {
    assert.deepEqual(verdict(quiet, { commentLines: 9, codeLines: 2 }).actions, ['trim']);
  });
});
