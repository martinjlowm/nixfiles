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
  /** unit -> definition -> per-instantiation size estimate (see `definitionSizes`) */
  definitions?: Map<string, Map<string, number>>;
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
  'as async block body closure const coroutine dyn extern fn for impl mut of static unsafe Self'.split(' '),
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
 * The definition an item instantiates: every generic argument list collapsed
 * to `<…>`, and the function's own trailing arguments dropped. A qualified
 * self type stays, so `<std::boxed::Box<String> as Drop>::drop` becomes
 * `<std::boxed::Box<…> as Drop>::drop` rather than `<…>::drop`.
 *
 * rustc's `-Z dump-mono-stats` names its rows the same way once normalized
 * by this function, which is how an item finds its size estimate. Grouping
 * and sizing only: identity is always the full signature.
 */
export function definitionOf(item: string): string {
  const unprefixed = item.replace(/^(fn|static) /, '');
  const shim = unprefixed.indexOf(' - shim');
  const s = shim === -1 ? unprefixed : unprefixed.slice(0, shim);
  let out = '';
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i] ?? '';
    const prev = s[i - 1] ?? '';
    if (depth > 0) {
      depth += bracketStep(ch, prev);
    } else if (ch === '<' && /[\w:]/.test(prev)) {
      out += '<…>';
      depth = 1;
    } else {
      out += ch;
    }
  }
  return out.replace(/::<…>$/, '');
}

/** How a character moves the bracket depth; the `>` of a `->` does not. */
const bracketStep = (ch: string, prev: string) => {
  if (ch === '<') {
    return 1;
  }
  return ch === '>' && prev !== '-' ? -1 : 0;
};

/** Per-instantiation size estimates from one unit's stats table, by definition. */
export function definitionSizes(stats: unknown, normalize: (name: string) => string) {
  const sums = new Map<string, { total: number; count: number }>();
  if (Array.isArray(stats)) {
    for (const row of stats) {
      if (typeof row?.name !== 'string') {
        continue;
      }
      const key = definitionOf(normalize(row.name));
      const sum = sums.get(key) ?? { total: 0, count: 0 };
      sums.set(key, sum);
      sum.total += Number(row.total_estimate) || 0;
      sum.count += Number(row.instantiation_count) || 0;
    }
  }
  const sizes = new Map<string, number>();
  for (const [key, { total, count }] of sums) {
    if (count > 0) {
      sizes.set(key, total / count);
    }
  }
  return sizes;
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

/**
 * One item whose duplication the change moved. Duplication is the copies
 * beyond the first: an item compiled in three units carries two.
 */
export type Change = {
  item: string;
  definition: string;
  baseUnits: string[];
  headUnits: string[];
  /** units that started compiling it (a regression) or stopped (a resolution) */
  units: string[];
  /** duplicate copies added or removed, always positive */
  copies: number;
  /** copies times the item's size estimate, null when no stats row matched */
  size: number | null;
};

export type UnitDelta = {
  unit: string;
  baseItems: number | null;
  headItems: number | null;
  baseSize: number | null;
  headSize: number | null;
};

export type Totals = {
  addedCopies: number;
  removedCopies: number;
  addedSize: number;
  removedSize: number;
  /** share of added and removed copies whose size is known */
  sized: number;
};

export type Comparison = {
  totals: Totals;
  regressions: Change[];
  resolutions: Change[];
  units: UnitDelta[];
};

const sorted = (units: Iterable<string>) => [...units].sort();
const extra = (units: number) => Math.max(units - 1, 0);

function sizeIn(side: Side, definition: string, units: string[]): number | null {
  const known = units
    .map((unit) => side.definitions?.get(unit)?.get(definition))
    .filter((size): size is number => size !== undefined);
  if (known.length === 0) {
    return null;
  }
  return known.reduce((a, b) => a + b, 0) / known.length;
}

export function compare(base: Side, head: Side, interner: Interner): Comparison {
  const baseByItem = unitsByItem(base);
  const headByItem = unitsByItem(head);
  const none = new Set<string>();

  const regressions: Change[] = [];
  const resolutions: Change[] = [];
  for (const id of new Set([...baseByItem.keys(), ...headByItem.keys()])) {
    const baseUnits = baseByItem.get(id) ?? none;
    const headUnits = headByItem.get(id) ?? none;
    const moved = extra(headUnits.size) - extra(baseUnits.size);
    if (moved === 0) {
      continue;
    }
    const item = interner.names[id] ?? '';
    const definition = definitionOf(item);
    const added = moved > 0;
    const units = added
      ? [...headUnits].filter((unit) => !baseUnits.has(unit))
      : [...baseUnits].filter((unit) => !headUnits.has(unit));
    const each = sizeIn(added ? head : base, definition, units);
    (added ? regressions : resolutions).push({
      item,
      definition,
      baseUnits: sorted(baseUnits),
      headUnits: sorted(headUnits),
      units: units.sort(),
      copies: Math.abs(moved),
      size: each === null ? null : each * Math.abs(moved),
    });
  }
  const bySize = (a: Change, b: Change) =>
    (b.size ?? 0) - (a.size ?? 0) || b.copies - a.copies || a.item.localeCompare(b.item);
  regressions.sort(bySize);
  resolutions.sort(bySize);

  const sum = (changes: Change[], f: (c: Change) => number) => changes.reduce((n, c) => n + f(c), 0);
  const allCopies = sum(regressions, (c) => c.copies) + sum(resolutions, (c) => c.copies);
  const sizedCopies =
    sum(regressions, (c) => (c.size === null ? 0 : c.copies)) +
    sum(resolutions, (c) => (c.size === null ? 0 : c.copies));
  const totals: Totals = {
    addedCopies: sum(regressions, (c) => c.copies),
    removedCopies: sum(resolutions, (c) => c.copies),
    addedSize: sum(regressions, (c) => c.size ?? 0),
    removedSize: sum(resolutions, (c) => c.size ?? 0),
    sized: allCopies === 0 ? 1 : sizedCopies / allCopies,
  };

  const units = sorted(new Set([...base.units.keys(), ...head.units.keys()])).map((unit) => ({
    unit,
    baseItems: base.units.get(unit)?.size ?? null,
    headItems: head.units.get(unit)?.size ?? null,
    baseSize: base.sizes.get(unit) ?? null,
    headSize: head.sizes.get(unit) ?? null,
  }));

  return { totals, regressions, resolutions, units };
}

export type Group = {
  definition: string;
  items: number;
  copies: number;
  size: number;
  units: string[];
  example: string;
};

/** Changes grouped by definition, largest estimated size first. */
export function groups(changes: Change[]): Group[] {
  const byDefinition = new Map<string, Group & { unitSet: Set<string> }>();
  for (const c of changes) {
    const g = byDefinition.get(c.definition) ?? {
      definition: c.definition,
      items: 0,
      copies: 0,
      size: 0,
      units: [],
      unitSet: new Set<string>(),
      example: c.item,
    };
    byDefinition.set(c.definition, g);
    g.items++;
    g.copies += c.copies;
    g.size += c.size ?? 0;
    for (const unit of c.units) {
      g.unitSet.add(unit);
    }
  }
  return [...byDefinition.values()]
    .map(({ unitSet, ...g }) => ({ ...g, units: sorted(unitSet) }))
    .sort((a, b) => b.size - a.size || b.copies - a.copies || a.definition.localeCompare(b.definition));
}

/** How the comparison was produced, for the line that lets an author rerun it. */
export type Run = {
  command?: string;
  system?: string;
};

const number = (n: number) => Math.round(n).toLocaleString('en-US');
const signed = (n: number) => (n > 0 ? `+${number(n)}` : n < 0 ? `−${number(-n)}` : '0');
const code = (s: string) => `\`${s.replaceAll('`', "'")}\``;
const clip = (s: string, max = 120) => (s.length > max ? `${s.slice(0, max - 1)}…` : s);
const unitList = (units: string[], max = 3) =>
  units.slice(0, max).map(code).join(', ') + (units.length > max ? `, +${units.length - max} more` : '');

function groupTable(title: string, column: string, list: Group[], top: number): string[] {
  if (list.length === 0) {
    return [];
  }
  const lines = [`#### ${title}`, ''];
  lines.push(`| Definition | Copies | Size estimate | ${column} | Example |`);
  lines.push('| --- | ---: | ---: | --- | --- |');
  for (const g of list.slice(0, top)) {
    lines.push(
      `| ${code(clip(g.definition, 90))} | ${number(g.copies)} | ${g.size > 0 ? number(g.size) : '–'} | ${unitList(g.units)} | ${code(clip(g.example))} |`,
    );
  }
  if (list.length > top) {
    lines.push('', `${number(list.length - top)} more definitions in regressions.json.`);
  }
  lines.push('');
  return lines;
}

/**
 * The report: duplication added against duplication removed, what added the
 * most, what removed the most, the units that moved, and how to rerun it.
 */
export function render(comparison: Comparison, run: Run = {}, top = 10): string {
  const { totals, regressions, resolutions, units } = comparison;
  const lines: string[] = [];

  const net = totals.addedCopies - totals.removedCopies;
  const netSize = totals.addedSize - totals.removedSize;
  lines.push(
    `**Duplicated codegen:** ${signed(totals.addedCopies)} copies added, ` +
      `${signed(-totals.removedCopies)} removed, net ${signed(net)}. ` +
      `Size estimate ${signed(totals.addedSize)} / ${signed(-totals.removedSize)}, net ${signed(netSize)}` +
      (totals.sized < 0.95 ? ` (${Math.round(totals.sized * 100)}% of copies sized)` : '') +
      '.',
    '',
  );

  lines.push(...groupTable('Added duplication', 'Now also compiled in', groups(regressions), top));
  lines.push(...groupTable('Removed duplication', 'No longer compiled in', groups(resolutions), Math.min(top, 5)));

  const changed = units
    .filter((u) => u.baseItems !== u.headItems || u.baseSize !== u.headSize)
    .sort(
      (a, b) =>
        Math.abs((b.headSize ?? 0) - (b.baseSize ?? 0)) - Math.abs((a.headSize ?? 0) - (a.baseSize ?? 0)) ||
        a.unit.localeCompare(b.unit),
    );
  if (changed.length > 0) {
    lines.push('#### Units', '');
    lines.push('| Unit | Items | Δ items | Δ size estimate |');
    lines.push('| --- | ---: | ---: | ---: |');
    for (const u of changed.slice(0, top)) {
      const items = u.headItems ?? u.baseItems ?? 0;
      lines.push(
        `| ${code(u.unit)} | ${number(items)} | ${signed((u.headItems ?? 0) - (u.baseItems ?? 0))} | ${signed((u.headSize ?? 0) - (u.baseSize ?? 0))} |`,
      );
    }
    if (changed.length > top) {
      lines.push('', `${number(changed.length - top)} more units changed.`);
    }
    lines.push('');
  }

  if (run.command) {
    lines.push(
      `Reproduce from a checkout of the repository${run.system ? ` (measured on \`${run.system}\`)` : ''}:`,
      '',
      '```',
      run.command,
      '```',
      '',
    );
  }

  return lines.join('\n');
}
