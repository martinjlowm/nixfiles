import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

import {
  type Checks,
  cropFor,
  cropFromBox,
  domViolations,
  type Element,
  fitImage,
  type JevSignals,
  jevVerdicts,
  offGrid,
  overallVerdict,
  type Probe,
} from './design.ts';

const checks = (JSON.parse(readFileSync(join(import.meta.dirname, 'rubric.json'), 'utf8')) as { checks: Checks })
  .checks;

const element = (overrides: Partial<Element> = {}): Element => ({
  tag: 'div',
  classes: 'MuiBox-root',
  testid: '',
  text: '',
  rect: { left: 0, top: 0, width: 100, height: 100 },
  ...overrides,
});

const probe = (overrides: Partial<Probe> = {}): Probe => ({
  devicePixelRatio: 1,
  viewport: { width: 1440, height: 900 },
  root: element(),
  spacing: [],
  radii: [],
  inputs: [],
  fonts: [{ family: 'Inter', count: 3, sample: element() }],
  ...overrides,
});

const quiet: JevSignals = { typeface: 0.04, outlinedInput: 0.02, overflow: 0.02, offPalette: 0.02 };

describe('offGrid', () => {
  it('accepts half steps of the 8px unit and sub-pixel rounding', () => {
    for (const value of [0, 4, 8, 12, 20, 40, -16, 16.3]) {
      assert.equal(offGrid(value, checks), false, `${value}`);
    }
  });

  it('rejects values between half steps', () => {
    for (const value of [2, 5, 10, 13, 18, -6]) {
      assert.equal(offGrid(value, checks), true, `${value}`);
    }
  });
});

describe('domViolations', () => {
  it('names each off-grid property with its value', () => {
    const violations = domViolations(
      probe({
        spacing: [
          { ...element({ text: 'Save' }), values: { paddingTop: 13, paddingLeft: 16, rowGap: null } },
          { ...element(), values: { paddingTop: 8 } },
        ],
      }),
      checks,
    );
    assert.equal(violations.length, 1);
    assert.equal(violations[0].rule, 'spacing');
    assert.match(violations[0].evidence, /^paddingTop 13px, not a multiple of 4px$/);
  });

  it('flags a surface radius the theme does not set', () => {
    const violations = domViolations(
      probe({ radii: [{ ...element({ classes: 'MuiPaper-root MuiPaper-rounded' }), radius: 4 }] }),
      checks,
    );
    assert.deepEqual(
      violations.map((v) => v.rule),
      ['radius'],
    );
  });

  it('flags an outlined form input but not an outlined data grid input', () => {
    const violations = domViolations(
      probe({
        inputs: [
          { ...element(), variant: 'outlined', inDataGrid: false },
          { ...element(), variant: 'outlined', inDataGrid: true },
          { ...element(), variant: 'filled', inDataGrid: false },
        ],
      }),
      checks,
    );
    assert.equal(violations.length, 1);
    assert.match(violations[0].evidence, /^outlined input, theme default is filled$/);
  });

  it('flags text set outside the theme typefaces', () => {
    const violations = domViolations(
      probe({ fonts: [{ family: 'Times New Roman', count: 2, sample: element() }] }),
      checks,
    );
    assert.deepEqual(
      violations.map((v) => v.rule),
      ['font'],
    );
  });
});

describe('crops', () => {
  it('pads the element rect, scales by device pixels and stays inside the image', () => {
    const crop = cropFor({ left: 10, top: 100, width: 200, height: 50 }, 2, { width: 400, height: 1000 }, 16);
    assert.deepEqual(crop, { x: 0, y: 168, width: 400, height: 164 });
  });

  it('converts a Jev box from fractions to pixels', () => {
    const crop = cropFromBox({ left: 0.25, top: 0.5, right: 0.75, bottom: 1 }, { width: 1000, height: 800 }, 0);
    assert.deepEqual(crop, { x: 250, y: 400, width: 500, height: 400 });
  });

  it('fits a canvas inside the 280 to 1568 pixel sides Jev accepts', () => {
    assert.deepEqual(fitImage({ width: 2880, height: 1800 }), { width: 1568, height: 980 });
    assert.deepEqual(fitImage({ width: 120, height: 40 }), { width: 280, height: 280 });
    assert.deepEqual(fitImage({ width: 3000, height: 60 }), { width: 1568, height: 280 });
  });

  it('enlarges a small crop at most twofold', () => {
    assert.deepEqual(fitImage({ width: 752, height: 357 }), { width: 1504, height: 714 });
    assert.deepEqual(fitImage({ width: 1000, height: 500 }), { width: 1568, height: 784 });
  });
});

describe('verdict', () => {
  it('complies when neither the DOM nor Jev finds anything', () => {
    assert.equal(overallVerdict([], jevVerdicts(quiet)), 'complies');
  });

  it('deviates on a DOM violation even when Jev agrees or did not run', () => {
    const violation = { rule: 'spacing' as const, element: element(), evidence: 'paddingTop 13px' };
    assert.equal(overallVerdict([violation], jevVerdicts(quiet)), 'deviates');
    assert.equal(overallVerdict([violation], null), 'deviates');
  });

  it('deviates when Jev disagrees and asks for review in the uncertain band', () => {
    assert.equal(overallVerdict([], jevVerdicts({ ...quiet, overflow: 0.96 })), 'deviates');
    assert.equal(overallVerdict([], jevVerdicts({ ...quiet, offPalette: 0.5 })), 'review');
  });

  it('asks for review when Jev did not run and the DOM found nothing', () => {
    assert.equal(overallVerdict([], null), 'review');
  });
});
