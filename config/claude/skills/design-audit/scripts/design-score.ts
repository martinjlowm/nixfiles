#!/usr/bin/env node
// Audits one component of a screen against the design-system rubric: DOM
// checks code settles, then Jev's judgement of a crop of the component.
// Usage and what to do with the result are in ../SKILL.md.
//
//   node design-score.ts --session <s> --selector <css> --target <what> --out <dir> [--text]
//   node design-score.ts --screenshot <png> --target <what> --out <dir> [--text]
//
// Node strips the types itself, so this runs from the store with no build step.
import { execFileSync } from 'node:child_process';
import { openAsBlob, readFileSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';

import {
  type Crop,
  type Checks,
  cropFor,
  cropFromBox,
  cropScale,
  DEFAULT_THRESHOLDS,
  domViolations,
  fitImage,
  IMAGE_SIDE_MAX_PX,
  type JevSignals,
  jevVerdicts,
  overallVerdict,
  type Probe,
  type Violation,
} from './design.ts';

const JEV_URL = 'https://api.typesafe.ai/v1/systemone';
// Images and Box questions need Jev 1.14 and the danger-zone header.
const JEV_MODEL = 'jev-1.14.0';
const MAX_ATTEMPTS = 5;
const CROP_PAD_PX = 16;
const BOX_PAD_FRACTION = 0.02;
const TARGET_PRESENT_MIN = 0.5;

const here = import.meta.dirname;

// Each question names one visible way a component departs from the design
// system, so a yes is a finding. Jev 1.14 does not resolve gaps of a few
// pixels in a screenshot, so spacing, alignment and corner radius are the DOM
// probe's alone. `component` is the crop.
const DESIGN_QUESTIONS = {
  typeface: {
    type: 'noul',
    instructions:
      'Is any text in `component` set in a serif typeface, or in a typeface other than a clean sans-serif like Inter?',
  },
  outlinedInput: {
    type: 'noul',
    instructions:
      'Are the text fields in `component` drawn as outlined boxes with a thin border on all four sides, rather than with a filled grey background and an underline?',
  },
  overflow: {
    type: 'noul',
    instructions: 'Is any text in `component` cut off mid-word, clipped by its container, or overlapping another element?',
  },
  offPalette: {
    type: 'noul',
    instructions:
      'Does `component` use a colour for a button, link or accent that is not purple, magenta, red, yellow, blue, green or grey?',
  },
} as const;

type Answer =
  | { type: 'noul'; noul: number }
  | { type: 'score'; score: number; confidence: number }
  | { type: 'box'; box: { top: number; bottom: number; left: number; right: number }; confidence: number };

async function askJev(
  state: Record<string, unknown>,
  questions: Record<string, unknown>,
  images: Record<string, string>,
): Promise<Record<string, Answer>> {
  const key = process.env.TYPESAFE_API_KEY;
  if (!key) {
    throw new Error('TYPESAFE_API_KEY is not set');
  }
  const assets: Record<string, { type: 'image'; part: string }> = {};
  const parts: [string, string][] = [];
  for (const [reference, path] of Object.entries(images)) {
    const part = `image-${parts.length}`;
    assets[reference] = { type: 'image', part };
    parts.push([part, path]);
  }
  for (let attempt = 1; ; attempt++) {
    const form = new FormData();
    form.append(
      'request',
      new Blob([JSON.stringify({ model: JEV_MODEL, state, assets, questions })], { type: 'application/json' }),
    );
    for (const [part, path] of parts) {
      form.append(part, await openAsBlob(path, { type: 'image/png' }), basename(path));
    }
    const response = await fetch(JEV_URL, {
      method: 'POST',
      headers: { authorization: `Bearer ${key}`, 'TypeSafe-Danger-Zone-Images': 'true' },
      body: form,
      signal: AbortSignal.timeout(90_000),
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

function imageSize(path: string): { width: number; height: number } {
  const [width, height] = execFileSync('magick', ['identify', '-format', '%w %h', path], { encoding: 'utf8' })
    .trim()
    .split(' ')
    .map(Number);
  return { width, height };
}

function prepareImage(source: string, crop: Crop | null, destination: string): void {
  const region = crop ?? { x: 0, y: 0, ...imageSize(source) };
  const { width, height } = fitImage(region);
  execFileSync('magick', [
    source,
    '-crop',
    `${region.width}x${region.height}+${region.x}+${region.y}`,
    '+repage',
    '-resize',
    `${Math.min(IMAGE_SIDE_MAX_PX, Math.round(region.width * cropScale(region)))}x${IMAGE_SIDE_MAX_PX}`,
    '-background',
    'white',
    '-gravity',
    'center',
    '-extent',
    `${width}x${height}`,
    `PNG24:${destination}`,
  ]);
}

function browser(session: string, ...args: string[]): string {
  return execFileSync('agent-browser', ['--session', session, ...args], { encoding: 'utf8' });
}

function runProbe(session: string, selector: string, checks: Checks): Probe {
  const source = readFileSync(join(here, 'probe.js'), 'utf8').trim();
  const call = `${source}(${JSON.stringify(selector)}, ${JSON.stringify(checks)})`;
  const result = JSON.parse(browser(session, 'eval', call)) as Probe | { error: string };
  if ('error' in result) {
    throw new Error(result.error);
  }
  return result;
}

type Report = {
  target: string;
  verdict: ReturnType<typeof overallVerdict>;
  screenshot: string;
  crop: string;
  located: 'selector' | { box: Crop; confidence: number; present: number };
  violations: Violation[];
  signals: JevSignals | null;
  disagreements: ReturnType<typeof jevVerdicts>;
  jevError: string | undefined;
};

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      session: { type: 'string' },
      selector: { type: 'string' },
      screenshot: { type: 'string' },
      target: { type: 'string' },
      out: { type: 'string', default: '.' },
      rubric: { type: 'string', default: join(here, 'rubric.json') },
      name: { type: 'string', default: 'component' },
      text: { type: 'boolean', default: false },
    },
  });
  if (!values.target || !(values.screenshot || (values.session && values.selector))) {
    throw new Error('pass --target with either --session and --selector, or --screenshot');
  }
  const rubric = JSON.parse(readFileSync(values.rubric, 'utf8')) as { checks: Checks };
  const files = {
    // agent-browser resolves a relative path against its daemon's directory.
    screen: resolve(values.out, `${values.name}-screen.png`),
    scaled: join(values.out, `${values.name}-scaled.png`),
    crop: join(values.out, `${values.name}-crop.png`),
  };

  const component =
    values.session && values.selector
      ? probeAndCrop(values.session, values.selector, rubric.checks, files)
      : await locateAndCrop(values.screenshot as string, values.target, files);

  let signals: JevSignals | null = null;
  let jevError: string | undefined;
  try {
    signals = await askDesignQuestions(files.crop);
  } catch (error) {
    jevError = String(error);
  }
  const disagreements = signals ? jevVerdicts(signals, DEFAULT_THRESHOLDS) : null;
  const report: Report = {
    target: values.target,
    verdict: overallVerdict(component.violations, disagreements),
    crop: files.crop,
    ...component,
    signals,
    disagreements: disagreements ?? [],
    jevError,
  };

  writeFileSync(join(values.out, `${values.name}-design.json`), `${JSON.stringify(report, null, 2)}\n`);
  console.log(values.text ? renderText(report) : JSON.stringify(report, null, 2));
}

type Component = Pick<Report, 'screenshot' | 'located' | 'violations'>;
type Files = { screen: string; scaled: string; crop: string };

function probeAndCrop(session: string, selector: string, checks: Checks, files: Files): Component {
  const probe = runProbe(session, selector, checks);
  browser(session, 'screenshot', files.screen);
  const crop = cropFor(probe.root.rect, probe.devicePixelRatio, imageSize(files.screen), CROP_PAD_PX);
  prepareImage(files.screen, crop, files.crop);
  return { screenshot: files.screen, located: 'selector', violations: domViolations(probe, checks) };
}

async function locateAndCrop(screenshot: string, target: string, files: Files): Promise<Component> {
  prepareImage(screenshot, null, files.scaled);
  const reference = crypto.randomUUID();
  const answers = await askJev(
    { screenshot: reference },
    {
      present: { type: 'noul', instructions: `Does \`screenshot\` show ${target}?` },
      where: { type: 'box', instructions: `${target} in \`screenshot\`` },
    },
    { [reference]: files.scaled },
  );
  const present = noulOf(answers, 'present');
  if (present < TARGET_PRESENT_MIN) {
    throw new Error(`Jev does not find ${target} in ${screenshot} (present ${present.toFixed(2)})`);
  }
  const where = answers.where as Extract<Answer, { type: 'box' }>;
  const box = cropFromBox(where.box, imageSize(screenshot), BOX_PAD_FRACTION);
  prepareImage(screenshot, box, files.crop);
  return { screenshot, located: { box, confidence: where.confidence, present }, violations: [] };
}

async function askDesignQuestions(crop: string): Promise<JevSignals> {
  const reference = crypto.randomUUID();
  const answers = await askJev({ component: reference }, DESIGN_QUESTIONS, { [reference]: crop });
  return {
    typeface: noulOf(answers, 'typeface'),
    outlinedInput: noulOf(answers, 'outlinedInput'),
    overflow: noulOf(answers, 'overflow'),
    offPalette: noulOf(answers, 'offPalette'),
  };
}

function noulOf(answers: Record<string, Answer>, id: string): number {
  return (answers[id] as Extract<Answer, { type: 'noul' }>).noul;
}

function renderText(report: Report): string {
  const lines = [`${report.target}: ${report.verdict}`, `  crop ${report.crop}`];
  if (typeof report.located !== 'string') {
    lines.push(`  located by Jev box, confidence ${report.located.confidence.toFixed(2)}`);
  }
  for (const v of report.violations) {
    const where = v.element.testid || v.element.classes || v.element.tag;
    lines.push(`  dom ${v.rule}: ${v.evidence} (${where}${v.element.text ? ` "${v.element.text}"` : ''})`);
  }
  for (const d of report.disagreements) {
    lines.push(`  jev ${d.verdict} ${d.signal} ${d.value.toFixed(2)}`);
  }
  if (report.jevError) {
    lines.push(`  jev did not run: ${report.jevError}`);
  }
  return lines.join('\n');
}

main().catch((error) => {
  console.error(String(error));
  process.exit(1);
});
