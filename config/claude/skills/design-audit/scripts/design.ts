// The checks code can settle from the DOM, the crop geometry Jev's image
// limits impose, and the rule that turns both into a verdict.

export type Rect = { left: number; top: number; width: number; height: number };

export type Element = { tag: string; classes: string; testid: string; text: string; rect: Rect };

export type Probe = {
  devicePixelRatio: number;
  viewport: { width: number; height: number };
  root: Element;
  spacing: (Element & { values: Record<string, number | null> })[];
  radii: (Element & { radius: number | null })[];
  inputs: (Element & { variant: 'outlined' | 'filled'; inDataGrid: boolean })[];
  fonts: { family: string; count: number; sample: Element }[];
};

export type Checks = {
  spacingStepPx: number;
  spacingTolerancePx: number;
  layoutClassPattern: string;
  marginSkipClassPattern: string;
  roundedRadiusPx: number;
  fontFamilies: string[];
  inputVariant: string;
  dataGridInputVariant: string;
};

export type Violation = { rule: 'spacing' | 'radius' | 'font' | 'input-variant'; element: Element; evidence: string };

export function offGrid(valuePx: number, checks: Checks): boolean {
  const remainder = Math.abs(valuePx) % checks.spacingStepPx;
  return Math.min(remainder, checks.spacingStepPx - remainder) > checks.spacingTolerancePx;
}

export function domViolations(probe: Probe, checks: Checks): Violation[] {
  const violations: Violation[] = [];
  for (const el of probe.spacing) {
    const off = Object.entries(el.values).filter(
      (entry): entry is [string, number] => entry[1] !== null && offGrid(entry[1], checks),
    );
    if (off.length > 0) {
      const evidence = off.map(([property, value]) => `${property} ${round(value)}px`).join(', ');
      violations.push({
        rule: 'spacing',
        element: el,
        evidence: `${evidence}, not a multiple of ${checks.spacingStepPx}px`,
      });
    }
  }
  for (const el of probe.radii) {
    if (el.radius !== null && el.radius !== checks.roundedRadiusPx) {
      violations.push({
        rule: 'radius',
        element: el,
        evidence: `border-radius ${round(el.radius)}px, theme rounds surfaces ${checks.roundedRadiusPx}px`,
      });
    }
  }
  const allowed = new Set(checks.fontFamilies.map((f) => f.toLowerCase()));
  for (const font of probe.fonts) {
    if (!allowed.has(font.family.toLowerCase())) {
      violations.push({
        rule: 'font',
        element: font.sample,
        evidence: `${font.count} text element(s) set in ${font.family}, theme sets ${checks.fontFamilies[0]}`,
      });
    }
  }
  for (const el of probe.inputs) {
    const expected = el.inDataGrid ? checks.dataGridInputVariant : checks.inputVariant;
    if (el.variant !== expected) {
      violations.push({
        rule: 'input-variant',
        element: el,
        evidence: `${el.variant} input${el.inDataGrid ? ' in a data grid' : ''}, theme default is ${expected}`,
      });
    }
  }
  return violations;
}

// Jev rejects an image with a side under 280px or over 1568px, and never
// resizes one to fit.
export const IMAGE_SIDE_MIN_PX = 280;
export const IMAGE_SIDE_MAX_PX = 1568;

export type Crop = { x: number; y: number; width: number; height: number };

// Jev reads a typeface or a clipped word more reliably from a crop scaled up,
// so a small crop is enlarged up to twice its size within the largest side.
export const CROP_UPSCALE_MAX = 2;

export function cropScale(region: { width: number; height: number }): number {
  return Math.min(CROP_UPSCALE_MAX, IMAGE_SIDE_MAX_PX / Math.max(region.width, region.height));
}

export function fitImage(region: { width: number; height: number }): { width: number; height: number } {
  const scale = cropScale(region);
  return {
    width: Math.max(IMAGE_SIDE_MIN_PX, Math.round(region.width * scale)),
    height: Math.max(IMAGE_SIDE_MIN_PX, Math.round(region.height * scale)),
  };
}

export function cropFor(rect: Rect, devicePixelRatio: number, image: { width: number; height: number }, padPx: number): Crop {
  const left = Math.max(0, Math.floor((rect.left - padPx) * devicePixelRatio));
  const top = Math.max(0, Math.floor((rect.top - padPx) * devicePixelRatio));
  const right = Math.min(image.width, Math.ceil((rect.left + rect.width + padPx) * devicePixelRatio));
  const bottom = Math.min(image.height, Math.ceil((rect.top + rect.height + padPx) * devicePixelRatio));
  return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) };
}

export function cropFromBox(
  box: { left: number; top: number; right: number; bottom: number },
  image: { width: number; height: number },
  padFraction: number,
): Crop {
  const left = Math.max(0, Math.floor((box.left - padFraction) * image.width));
  const top = Math.max(0, Math.floor((box.top - padFraction) * image.height));
  const right = Math.min(image.width, Math.ceil((box.right + padFraction) * image.width));
  const bottom = Math.min(image.height, Math.ceil((box.bottom + padFraction) * image.height));
  return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) };
}

// The same verdict feeds a QA fix and a review comment, so a signal flips to a
// finding only past a threshold, and the band below it is left to the caller.
export const DEFAULT_THRESHOLDS = { disagree: 0.7, uncertain: 0.4 };

export type JevSignals = {
  typeface: number;
  outlinedInput: number;
  overflow: number;
  offPalette: number;
};

export type SignalVerdict = { signal: keyof JevSignals; value: number; verdict: 'disagree' | 'uncertain' };

export function jevVerdicts(signals: JevSignals, thresholds = DEFAULT_THRESHOLDS): SignalVerdict[] {
  const verdicts: SignalVerdict[] = [];
  for (const [signal, value] of Object.entries(signals) as [keyof JevSignals, number][]) {
    if (value >= thresholds.disagree) {
      verdicts.push({ signal, value, verdict: 'disagree' });
    } else if (value >= thresholds.uncertain) {
      verdicts.push({ signal, value, verdict: 'uncertain' });
    }
  }
  return verdicts;
}

export type Verdict = 'complies' | 'deviates' | 'review';

// `verdicts` is null when Jev did not answer.
export function overallVerdict(violations: Violation[], verdicts: SignalVerdict[] | null): Verdict {
  if (violations.length > 0 || verdicts?.some((v) => v.verdict === 'disagree')) {
    return 'deviates';
  }
  return verdicts === null || verdicts.length > 0 ? 'review' : 'complies';
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}
