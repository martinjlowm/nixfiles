import { describe, expect, test } from 'bun:test';

import {
  compare,
  definitionOf,
  definitionSizes,
  Interner,
  itemOf,
  qualify,
  render,
  type Side,
  sizeOf,
} from './compare.ts';

function side(interner: Interner, units: Record<string, string[]>): Side {
  return {
    units: new Map(
      Object.entries(units).map(([unit, items]) => [unit, new Set(items.map((item) => interner.id(item)))]),
    ),
    sizes: new Map(Object.keys(units).map((unit) => [unit, 0])),
  };
}

describe('itemOf', () => {
  test('drops the codegen-unit placement, which carries a per-build hash', () => {
    expect(itemOf('MONO_ITEM fn generic_heavy::<i32> @@ mylib.b1c64a03052da605-cgu.0[Internal]')).toBe(
      'fn generic_heavy::<i32>',
    );
  });

  test('keeps an item placed in several codegen units whole', () => {
    expect(itemOf('MONO_ITEM fn f::<u8> @@ a-cgu.0[Internal] a-cgu.3[Internal]')).toBe('fn f::<u8>');
  });

  test('ignores anything that is not a MONO_ITEM line', () => {
    expect(itemOf('warning: unused variable')).toBeUndefined();
  });
});

describe('qualify', () => {
  const externs = new Set(['mylib', 'async_graphql', 'tokio']);

  // Both lines from one release build of a two-crate workspace: the same
  // instantiation, printed differently by the crate that owns it.
  test('makes an item compare equal from its own crate and from another', () => {
    expect(qualify('fn generic_heavy::<i32>', 'mylib.lib', new Set())).toBe('fn mylib::generic_heavy::<i32>');
    expect(qualify('fn mylib::generic_heavy::<i32>', 'mybin.bin', externs)).toBe('fn mylib::generic_heavy::<i32>');
  });

  test('qualifies local types inside generic arguments and trait paths', () => {
    expect(qualify('fn <Widget as async_graphql::OutputType>::create_type_info', 'reslib.lib', externs)).toBe(
      'fn <reslib::Widget as async_graphql::OutputType>::create_type_info',
    );
  });

  test("keeps a bin's own items apart from its package's lib", () => {
    expect(qualify('fn async_main::{closure#0}', 'app.bin', new Set(['app']))).toBe(
      'fn app[bin]::async_main::{closure#0}',
    );
    expect(qualify('fn app::serve::<u8>', 'app.bin', new Set(['app']))).toBe('fn app::serve::<u8>');
  });

  test('leaves std paths, primitives, impl headers, lifetimes and shims alone', () => {
    const item = 'fn <u8 as std::slice::<impl [T]>::to_vec_in::ConvertVec>::to_vec::<std::alloc::Global>';
    expect(qualify(item, 'a.lib', new Set())).toBe(item);
    expect(
      qualify(
        "fn <for<'a> fn(&'a str) -> bool as std::ops::FnOnce<(&str,)>>::call_once - shim(Foo)",
        'a.lib',
        new Set(),
      ),
    ).toBe("fn <for<'a> fn(&'a str) -> bool as std::ops::FnOnce<(&str,)>>::call_once - shim(Foo)");
  });

  test('qualifies the function an async body or closure belongs to', () => {
    expect(qualify('fn std::ptr::drop_in_place::<{async fn body of run()}>', 'a.lib', new Set())).toBe(
      'fn std::ptr::drop_in_place::<{async fn body of a::run()}>',
    );
  });
});

describe('definitionOf', () => {
  test('keeps the qualified self type and collapses its arguments', () => {
    expect(definitionOf('fn <std::boxed::Box<std::string::String> as std::ops::Drop>::drop')).toBe(
      '<std::boxed::Box<…> as std::ops::Drop>::drop',
    );
  });

  test("drops the function's own arguments and keeps an impl's", () => {
    expect(definitionOf('fn generic_heavy::<i32>')).toBe('generic_heavy');
    expect(definitionOf('fn alloc::raw_vec::RawVecInner::<std::alloc::Global>::grow')).toBe(
      'alloc::raw_vec::RawVecInner::<…>::grow',
    );
  });

  test('normalizes an item and its stats row to the same key', () => {
    expect(definitionOf('<std::boxed::Box<T, A> as std::ops::Drop>::drop')).toBe(
      definitionOf('fn <std::boxed::Box<anyhow::ErrorImpl<()>> as std::ops::Drop>::drop'),
    );
  });

  test('strips a shim description and ignores the arrow of a fn type', () => {
    expect(definitionOf('fn std::ptr::drop_in_place::<Foo> - shim(Some(Foo))')).toBe('std::ptr::drop_in_place');
    expect(definitionOf("fn <for<'a> fn(&'a str) -> String as FnOnce<(&str,)>>::call_once")).toBe(
      "<for<…> fn(&'a str) -> String as FnOnce<…>>::call_once",
    );
  });
});

describe('definitionSizes', () => {
  test('averages the per-instantiation estimate of rows sharing a definition', () => {
    const sizes = definitionSizes(
      [
        { name: 'a::wrap', instantiation_count: 3, size_estimate: 58, total_estimate: 174 },
        { name: 'b::f::<T>', instantiation_count: 1, total_estimate: 10 },
        { name: 'b::f::<U>', instantiation_count: 1, total_estimate: 30 },
      ],
      (name) => name,
    );
    expect(sizes.get('a::wrap')).toBe(58);
    expect(sizes.get('b::f')).toBe(20);
  });

  test('tolerates a missing table', () => {
    expect(definitionSizes(undefined, (name) => name).size).toBe(0);
  });
});

describe('sizeOf', () => {
  test('sums total_estimate and tolerates a missing table', () => {
    expect(sizeOf([{ total_estimate: 49 }, { total_estimate: 19 }])).toBe(68);
    expect(sizeOf(undefined)).toBe(0);
  });
});

describe('compare', () => {
  // A package split into lib and bin: with share-generics off, the bin
  // compiles its own private copy of what the lib already compiled.
  test('reports an item that a change makes a second unit compile', () => {
    const interner = new Interner();
    const base = side(interner, {
      'app/app.lib': ['fn generic_heavy::<i32>'],
      'app/app.bin': [],
    });
    const head = side(interner, {
      'app/app.lib': ['fn generic_heavy::<i32>'],
      'app/app.bin': ['fn generic_heavy::<i32>'],
    });

    const { regressions, resolutions, totals } = compare(base, head, interner);

    expect(regressions).toEqual([
      {
        item: 'fn generic_heavy::<i32>',
        definition: 'generic_heavy',
        baseUnits: ['app/app.lib'],
        headUnits: ['app/app.bin', 'app/app.lib'],
        units: ['app/app.bin'],
        copies: 1,
        size: null,
      },
    ]);
    expect(resolutions).toEqual([]);
    expect(totals.addedCopies).toBe(1);
    expect(totals.removedCopies).toBe(0);
  });

  // A name-only match would count these: block_on appears in both lib and
  // bin, but each instantiation takes a different future type.
  test('does not treat one definition with different type arguments as a duplicate', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': [], 'a/a.bin': [] });
    const head = side(interner, {
      'a/a.lib': ['fn block_on::<CpuRuntimeFuture>'],
      'a/a.bin': ['fn block_on::<AsyncMainFuture>'],
    });

    expect(compare(base, head, interner).regressions).toEqual([]);
  });

  test('counts each extra unit a duplicate spreads to', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'], 'c/c.lib': [] });
    const head = side(interner, { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'], 'c/c.lib': ['fn f'] });

    const [regression] = compare(base, head, interner).regressions;
    expect(regression?.copies).toBe(1);
    expect(regression?.units).toEqual(['c/c.lib']);
  });

  test('does not report a duplicate that was already there', () => {
    const interner = new Interner();
    const units = { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'] };

    const { regressions, resolutions } = compare(side(interner, units), side(interner, units), interner);
    expect(regressions).toEqual([]);
    expect(resolutions).toEqual([]);
  });

  // Boxing the futures a trait returns removes the consumer's copy.
  test('reports a duplicate the change removes as resolved', () => {
    const interner = new Interner();
    const base = side(interner, {
      'schema/schema.lib': ['fn resolve_field::<Widget>'],
      'app/app.lib': ['fn resolve_field::<Widget>'],
    });
    const head = side(interner, {
      'schema/schema.lib': ['fn resolve_field::<Widget>'],
      'app/app.lib': [],
    });

    const { regressions, resolutions } = compare(base, head, interner);
    expect(regressions).toEqual([]);
    expect(resolutions).toEqual([
      {
        item: 'fn resolve_field::<Widget>',
        definition: 'resolve_field',
        baseUnits: ['app/app.lib', 'schema/schema.lib'],
        headUnits: ['schema/schema.lib'],
        units: ['app/app.lib'],
        copies: 1,
        size: null,
      },
    ]);
  });

  // Three binaries recompiling a library's future, and two of them stop: the
  // duplicate survives, but two copies of it are gone.
  test('counts a duplicate that shrinks without disappearing as removed copies', () => {
    const interner = new Interner();
    const item = 'fn <{async fn body of lib::run()} as IntoFuture>::into_future';
    const base = side(interner, { 'x/x.bin': [item], 'y/y.bin': [item], 'z/z.bin': [item], 'lib/lib.lib': [item] });
    const head = side(interner, { 'x/x.bin': [], 'y/y.bin': [], 'z/z.bin': [item], 'lib/lib.lib': [item] });

    const { resolutions, totals } = compare(base, head, interner);
    expect(resolutions.map((r) => [r.copies, r.units])).toEqual([[2, ['x/x.bin', 'y/y.bin']]]);
    expect(totals.removedCopies).toBe(2);
  });

  test('weighs copies by the size estimate of the units that gained them', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn big::<u8>'], 'b/b.lib': [], 'c/c.lib': [] });
    const head = side(interner, {
      'a/a.lib': ['fn big::<u8>'],
      'b/b.lib': ['fn big::<u8>'],
      'c/c.lib': ['fn big::<u8>'],
    });
    head.definitions = new Map([
      ['b/b.lib', new Map([['big', 100]])],
      ['c/c.lib', new Map([['big', 300]])],
    ]);

    const { regressions, totals } = compare(base, head, interner);
    expect(regressions[0]?.copies).toBe(2);
    expect(regressions[0]?.size).toBe(400);
    expect(totals.addedSize).toBe(400);
    expect(totals.sized).toBe(1);
  });

  // A crate the PR adds exists only on head, and what it duplicates counts.
  test('counts duplicates in a unit that exists only on head', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn f'] });
    const head = side(interner, { 'a/a.lib': ['fn f'], 'new/new.lib': ['fn f'] });

    const { regressions, units } = compare(base, head, interner);
    expect(regressions.map((r) => r.units)).toEqual([['new/new.lib']]);
    expect(units.find((u) => u.unit === 'new/new.lib')).toEqual({
      unit: 'new/new.lib',
      baseItems: null,
      headItems: 1,
      baseSize: null,
      headSize: 0,
    });
  });
});

describe('render', () => {
  test('leads with added against removed copies and groups by definition', () => {
    const interner = new Interner();
    const base = side(interner, {
      'a/a.lib': ['fn g::<u8>', 'fn g::<u16>', 'fn h'],
      'b/b.lib': ['fn h'],
      'c/c.lib': ['fn h'],
    });
    const head = side(interner, {
      'a/a.lib': ['fn g::<u8>', 'fn g::<u16>', 'fn h'],
      'b/b.lib': ['fn g::<u8>', 'fn g::<u16>'],
      'c/c.lib': [],
    });

    const markdown = render(compare(base, head, interner));
    expect(markdown).toStartWith('**Duplicated codegen:** +2 copies added, −2 removed, net 0.');
    expect(markdown).toContain('#### Added duplication');
    expect(markdown).toContain('| `g` | 2 | – | `b/b.lib` |');
    expect(markdown).toContain('#### Removed duplication');
    expect(markdown).toContain('| `h` | 2 | – | `b/b.lib`, `c/c.lib` |');
  });

  test('ends with the command that reproduces it', () => {
    const interner = new Interner();
    const units = { 'a/a.lib': ['fn f'] };
    const markdown = render(compare(side(interner, units), side(interner, units), interner), {
      command: 'nix run github:martinjlowm/nixfiles/abc#agent-mono-items -- . b1 h1 /tmp/mono-items',
      system: 'x86_64-linux',
    });
    expect(markdown).toContain('Reproduce from a checkout of the repository (measured on `x86_64-linux`):');
    expect(markdown).toContain('nix run github:martinjlowm/nixfiles/abc#agent-mono-items -- . b1 h1 /tmp/mono-items');
  });

  test('says nothing moved when nothing did', () => {
    const interner = new Interner();
    const units = { 'a/a.lib': ['fn f'] };
    expect(render(compare(side(interner, units), side(interner, units), interner))).toBe(
      '**Duplicated codegen:** 0 copies added, 0 removed, net 0. Size estimate 0 / 0, net 0.\n',
    );
  });
});
