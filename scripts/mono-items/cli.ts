#!/usr/bin/env node
// Compares two mono-item reports and writes report.md and regressions.json.
//
//   node cli.ts <base-report> <head-report> <out-dir>
//
// Run by `agent-mono-items` (mono-items.sh) after both builds.
// Node strips the types itself, so this runs from the store with no build step.
import { createReadStream } from 'node:fs';
import { readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { compare, Interner, itemOf, qualify, render, type Side, sizeOf } from './compare.ts';

async function readSide(dir: string, interner: Interner): Promise<Side> {
  const side: Side = { units: new Map(), sizes: new Map() };
  for (const member of (await readdir(dir)).sort()) {
    const memberDir = join(dir, member);
    // Members are symlinks into the store; stat follows them.
    if (!(await stat(memberDir)).isDirectory()) continue;
    for (const file of (await readdir(memberDir)).sort()) {
      if (!file.endsWith('.items')) continue;
      const name = file.slice(0, -'.items'.length);
      const unit = `${member}/${name}`;
      const externs = new Set<string>(
        (await readFile(join(memberDir, `${name}.externs`), 'utf8').catch(() => ''))
          .split('\n')
          .filter(Boolean),
      );
      const items = new Set<number>();
      const lines = createInterface({ input: createReadStream(join(memberDir, file)) });
      for await (const line of lines) {
        const item = itemOf(line);
        if (item !== undefined) items.add(interner.id(qualify(item, name, externs)));
      }
      side.units.set(unit, items);
      const stats = await readFile(join(memberDir, `${name}.stats.json`), 'utf8')
        .then(JSON.parse)
        .catch(() => []);
      side.sizes.set(unit, sizeOf(stats));
    }
  }
  return side;
}

const [baseDir, headDir, outDir] = process.argv.slice(2);
if (!baseDir || !headDir || !outDir) {
  console.error('usage: cli.ts <base-report> <head-report> <out-dir>');
  process.exit(2);
}

const interner = new Interner();
const base = await readSide(baseDir, interner);
const head = await readSide(headDir, interner);
const comparison = compare(base, head, interner);

await writeFile(join(outDir, 'report.md'), render(comparison));
await writeFile(join(outDir, 'regressions.json'), `${JSON.stringify(comparison, null, 2)}\n`);
console.log(
  `${comparison.regressions.length} regressions, ${comparison.resolutions.length} resolutions, ${comparison.units.length} units`,
);
