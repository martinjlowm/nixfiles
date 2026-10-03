// Compares two mono-item reports written by mono-items.nix.
//
// A report is a directory per workspace member, each holding `<unit>.items`
// (rustc's MONO_ITEM lines for one compilation unit) and `<unit>.stats.json`
// (its `-Z dump-mono-stats` table). A unit is a crate's lib or bin target, so
// `app/app.lib` and `app/app.bin` are two units.
//
// An item is identified by its full signature, generic arguments included, with
// each unit's own paths qualified by its crate name (see `qualify`). Two
// instantiations of one function with different type arguments are different
// items, and only the same item compiled in two units is a duplicate: a
// generic reused across a crate boundary is a call into the crate that
// compiled it and never appears as an item of the caller.

export type Side = {
  /** unit -> item ids compiled in it */
  units: Map<string, Set<number>>;
  /** unit -> summed `total_estimate` from its stats table */
  sizes: Map<string, number>;
};

/** Item signatures interned once across both sides. */
export class Interner {
  readonly ids = new Map<string, number>();
  readonly names: string[] = [];

  id(name: string): number {
    let id = this.ids.get(name);
    if (id === undefined) {
      id = this.names.length;
      this.names.push(name);
      this.ids.set(name, id);
    }
    return id;
  }
}

/**
 * The item a MONO_ITEM line names, without the codegen-unit placement after
 * ` @@ `, which carries a per-build hash.
 */
export function itemOf(line: string): string | undefined {
  if (!line.startsWith('MONO_ITEM ')) return undefined;
  const at = line.lastIndexOf(' @@ ');
  return line.slice('MONO_ITEM '.length, at === -1 ? undefined : at);
}

// Crate roots every unit can name without an `--extern`.
const BUILTIN_CRATES = new Set(['std', 'core', 'alloc', 'proc_macro', 'test']);
const PRIMITIVES = new Set([
  ...['i8', 'i16', 'i32', 'i64', 'i128', 'isize'],
  ...['u8', 'u16', 'u32', 'u64', 'u128', 'usize'],
  ...['f16', 'f32', 'f64', 'f128', 'bool', 'char', 'str'],
]);
// Words rustc's item printer uses that are not paths: keywords, and the
// labels of closures and async bodies (`{closure#0}`, `{async fn body of f()}`).
const NOT_PATHS = new Set(
  'as async block body closure const coroutine dyn extern fn for impl mut of static unsafe Self'.split(
    ' ',
  ),
);

/**
 * The item with this unit's own paths qualified by its crate name.
 *
 * rustc prints an item of the crate being compiled without the crate's name,
 * and the same item compiled in another crate with it: `generic_heavy::<i32>`
 * in `mylib`, `mylib::generic_heavy::<i32>` in `mybin`. Qualifying both the
 * same way is what makes them compare equal.
 *
 * A path's first segment is another crate when it is one of `externs` or a
 * builtin crate, and this unit's otherwise. A bin's own paths take
 * `<crate>[bin]`, because a bin and its package's lib share a crate name while
 * the bin reaches the lib's items as `<crate>::…`. Generic parameters inside
 * `<impl …>` are left alone, and so is a shim's description after ` - shim`.
 */
export function qualify(item: string, unit: string, externs: ReadonlySet<string>): string {
  const dot = unit.indexOf('.');
  const crate = dot === -1 ? unit : unit.slice(0, dot);
  const own = unit
    .slice(dot + 1)
    .split(',')
    .includes('bin')
    ? `${crate}[bin]`
    : crate;

  const shim = item.indexOf(' - shim');
  const body = shim === -1 ? item : item.slice(0, shim);
  const rest = shim === -1 ? '' : item.slice(shim);

  let out = '';
  // One entry per open `<`: whether it opened an `<impl …>` header.
  const angles: boolean[] = [];
  let i = 0;
  while (i < body.length) {
    const ch = body[i] ?? '';
    if (ch === '<') {
      angles.push(body.startsWith('impl ', i + 1));
      out += ch;
      i++;
    } else if (ch === '>' && body[i - 1] !== '-') {
      angles.pop();
      out += ch;
      i++;
    } else if (/[A-Za-z_]/.test(ch)) {
      let end = i + 1;
      while (end < body.length && /\w/.test(body[end] ?? '')) end++;
      const ident = body.slice(i, end);
      const continuesPath = out.endsWith('::');
      const lifetime = out.endsWith("'");
      const local =
        !continuesPath &&
        !lifetime &&
        !angles.includes(true) &&
        !NOT_PATHS.has(ident) &&
        !PRIMITIVES.has(ident) &&
        !BUILTIN_CRATES.has(ident) &&
        !externs.has(ident);
      out += local ? `${own}::${ident}` : ident;
      i = end;
    } else if (/\w/.test(ch)) {
      // A digit run, such as the 0 in `{closure#0}`, is never a path.
      let end = i + 1;
      while (end < body.length && /\w/.test(body[end] ?? '')) end++;
      out += body.slice(i, end);
      i = end;
    } else {
      out += ch;
      i++;
    }
  }
  return out + rest;
}

/**
 * The item with every generic argument list collapsed, so the instantiations
 * of one definition group together in the report. Grouping only: identity is
 * always the full signature.
 */
export function familyOf(item: string): string {
  let out = '';
  let depth = 0;
  let previous = '';
  for (const ch of item) {
    const arrow = previous === '-';
    previous = ch;
    if (ch === '<') {
      if (depth === 0) out += '<…>';
      depth++;
    } else if (ch === '>' && !arrow && depth > 0) {
      depth--;
    } else if (depth === 0) {
      out += ch;
    }
  }
  return out;
}

export function sizeOf(stats: unknown): number {
  if (!Array.isArray(stats)) return 0;
  return stats.reduce((sum, row) => sum + (Number(row?.total_estimate) || 0), 0);
}

/** item id -> the units that compiled it */
export function unitsByItem(side: Side): Map<number, Set<string>> {
  const byItem = new Map<number, Set<string>>();
  for (const [unit, items] of side.units) {
    for (const item of items) {
      const units = byItem.get(item) ?? new Set<string>();
      byItem.set(item, units);
      units.add(unit);
    }
  }
  return byItem;
}

export type Regression = {
  item: string;
  family: string;
  /** `new` when the item was compiled in at most one unit on base */
  kind: 'new' | 'grown';
  baseUnits: string[];
  headUnits: string[];
  addedUnits: string[];
};

export type Resolution = {
  item: string;
  baseUnits: string[];
  headUnits: string[];
};

export type UnitDelta = {
  unit: string;
  baseItems: number | null;
  headItems: number | null;
  baseSize: number | null;
  headSize: number | null;
};

export type Comparison = {
  regressions: Regression[];
  resolutions: Resolution[];
  units: UnitDelta[];
};

const sorted = (units: Iterable<string>) => [...units].sort();

export function compare(base: Side, head: Side, interner: Interner): Comparison {
  const baseByItem = unitsByItem(base);
  const headByItem = unitsByItem(head);
  const none = new Set<string>();

  const regressions: Regression[] = [];
  for (const [id, headUnits] of headByItem) {
    if (headUnits.size < 2) continue;
    const baseUnits = baseByItem.get(id) ?? none;
    const added = [...headUnits].filter((unit) => !baseUnits.has(unit));
    if (added.length === 0) continue;
    const item = interner.names[id] ?? '';
    regressions.push({
      item,
      family: familyOf(item),
      kind: baseUnits.size < 2 ? 'new' : 'grown',
      baseUnits: sorted(baseUnits),
      headUnits: sorted(headUnits),
      addedUnits: added.sort(),
    });
  }
  regressions.sort(
    (a, b) => b.headUnits.length - a.headUnits.length || a.item.localeCompare(b.item),
  );

  const resolutions: Resolution[] = [];
  for (const [id, baseUnits] of baseByItem) {
    if (baseUnits.size < 2) continue;
    const headUnits = headByItem.get(id) ?? none;
    if (headUnits.size >= 2) continue;
    resolutions.push({
      item: interner.names[id] ?? '',
      baseUnits: sorted(baseUnits),
      headUnits: sorted(headUnits),
    });
  }
  resolutions.sort(
    (a, b) => b.baseUnits.length - a.baseUnits.length || a.item.localeCompare(b.item),
  );

  const units = sorted(new Set([...base.units.keys(), ...head.units.keys()])).map((unit) => ({
    unit,
    baseItems: base.units.get(unit)?.size ?? null,
    headItems: head.units.get(unit)?.size ?? null,
    baseSize: base.sizes.get(unit) ?? null,
    headSize: head.sizes.get(unit) ?? null,
  }));

  return { regressions, resolutions, units };
}

export type Family = {
  family: string;
  items: number;
  addedUnits: string[];
  example: string;
};

/** Regressions grouped by definition, largest group first. */
export function families(regressions: Regression[]): Family[] {
  const groups = new Map<string, { items: number; units: Set<string>; example: string }>();
  for (const r of regressions) {
    const group = groups.get(r.family) ?? { items: 0, units: new Set(), example: r.item };
    groups.set(r.family, group);
    group.items++;
    for (const unit of r.addedUnits) group.units.add(unit);
  }
  return [...groups]
    .map(([family, g]) => ({
      family,
      items: g.items,
      addedUnits: sorted(g.units),
      example: g.example,
    }))
    .sort((a, b) => b.items - a.items || a.family.localeCompare(b.family));
}

const count = (n: number | null) => (n === null ? '–' : n.toLocaleString('en-US'));
const delta = (base: number | null, head: number | null) => {
  if (base === null || head === null) return '–';
  const d = head - base;
  return d === 0 ? '0' : `${d > 0 ? '+' : ''}${d.toLocaleString('en-US')}`;
};
const code = (s: string) => `\`${s.replaceAll('`', "'")}\``;
const clip = (s: string, max = 160) => (s.length > max ? `${s.slice(0, max - 1)}…` : s);

export function render(comparison: Comparison, top = 25): string {
  const { regressions, resolutions, units } = comparison;
  const groups = families(regressions);
  const lines: string[] = [];

  lines.push(
    `${regressions.length.toLocaleString('en-US')} items newly compiled in more than one unit ` +
      `(${groups.length.toLocaleString('en-US')} definitions), ` +
      `${resolutions.length.toLocaleString('en-US')} duplicates resolved.`,
    '',
  );

  if (groups.length > 0) {
    lines.push('#### Newly duplicated, by definition', '');
    lines.push('| Definition | Items | Units it is now also compiled in | Example |');
    lines.push('| --- | ---: | --- | --- |');
    for (const g of groups.slice(0, top)) {
      lines.push(
        `| ${code(clip(g.family, 100))} | ${g.items} | ${g.addedUnits.map(code).join(', ')} | ${code(clip(g.example))} |`,
      );
    }
    if (groups.length > top) lines.push('', `${groups.length - top} more in regressions.json.`);
    lines.push('');
  }

  if (resolutions.length > 0) {
    lines.push('#### Resolved', '');
    lines.push('| Item | Base units | Head units |');
    lines.push('| --- | --- | --- |');
    for (const r of resolutions.slice(0, Math.min(top, 10))) {
      lines.push(
        `| ${code(clip(r.item))} | ${r.baseUnits.map(code).join(', ')} | ${r.headUnits.map(code).join(', ') || '–'} |`,
      );
    }
    lines.push('');
  }

  const changed = units.filter((u) => u.baseItems !== u.headItems || u.baseSize !== u.headSize);
  if (changed.length > 0) {
    lines.push('#### Units whose collection changed', '');
    lines.push('| Unit | Items, base | Items, head | Δ | Size estimate Δ |');
    lines.push('| --- | ---: | ---: | ---: | ---: |');
    for (const u of changed) {
      lines.push(
        `| ${code(u.unit)} | ${count(u.baseItems)} | ${count(u.headItems)} | ${delta(u.baseItems, u.headItems)} | ${delta(u.baseSize, u.headSize)} |`,
      );
    }
    lines.push('');
  }

  return lines.join('\n');
}
