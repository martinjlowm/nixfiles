import { describe, expect, test } from 'bun:test';
import {
  compare,
  familyOf,
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
      Object.entries(units).map(([unit, items]) => [
        unit,
        new Set(items.map((item) => interner.id(item))),
      ]),
    ),
    sizes: new Map(Object.keys(units).map((unit) => [unit, 0])),
  };
}

describe('itemOf', () => {
  test('drops the codegen-unit placement, which carries a per-build hash', () => {
    expect(
      itemOf('MONO_ITEM fn generic_heavy::<i32> @@ mylib.b1c64a03052da605-cgu.0[Internal]'),
    ).toBe('fn generic_heavy::<i32>');
  });

  test('keeps an item placed in several codegen units whole', () => {
    expect(itemOf('MONO_ITEM fn f::<u8> @@ a-cgu.0[Internal] a-cgu.3[Internal]')).toBe(
      'fn f::<u8>',
    );
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
    expect(qualify('fn generic_heavy::<i32>', 'mylib.lib', new Set())).toBe(
      'fn mylib::generic_heavy::<i32>',
    );
    expect(qualify('fn mylib::generic_heavy::<i32>', 'mybin.bin', externs)).toBe(
      'fn mylib::generic_heavy::<i32>',
    );
  });

  test('qualifies local types inside generic arguments and trait paths', () => {
    expect(
      qualify('fn <Widget as async_graphql::OutputType>::create_type_info', 'reslib.lib', externs),
    ).toBe('fn <reslib::Widget as async_graphql::OutputType>::create_type_info');
  });

  test("keeps a bin's own items apart from its package's lib", () => {
    expect(qualify('fn async_main::{closure#0}', 'app.bin', new Set(['app']))).toBe(
      'fn app[bin]::async_main::{closure#0}',
    );
    expect(qualify('fn app::serve::<u8>', 'app.bin', new Set(['app']))).toBe(
      'fn app::serve::<u8>',
    );
  });

  test('leaves std paths, primitives, impl headers, lifetimes and shims alone', () => {
    const item =
      'fn <u8 as std::slice::<impl [T]>::to_vec_in::ConvertVec>::to_vec::<std::alloc::Global>';
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
    expect(
      qualify('fn std::ptr::drop_in_place::<{async fn body of run()}>', 'a.lib', new Set()),
    ).toBe('fn std::ptr::drop_in_place::<{async fn body of a::run()}>');
  });
});

describe('familyOf', () => {
  test('collapses nested generic arguments', () => {
    expect(familyOf('fn <&mut PollFn<{closure@a<B>}> as DerefMut>::deref_mut')).toBe(
      'fn <…>::deref_mut',
    );
    expect(familyOf('fn generic_heavy::<i32>')).toBe('fn generic_heavy::<…>');
  });

  test('does not read the arrow of a fn type as a closing bracket', () => {
    expect(familyOf("fn <for<'a> fn(&'a str) -> String as FnOnce<(&str,)>>::call_once")).toBe(
      'fn <…>::call_once',
    );
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

    const { regressions, resolutions } = compare(base, head, interner);

    expect(regressions).toEqual([
      {
        item: 'fn generic_heavy::<i32>',
        family: 'fn generic_heavy::<…>',
        kind: 'new',
        baseUnits: ['app/app.lib'],
        headUnits: ['app/app.bin', 'app/app.lib'],
        addedUnits: ['app/app.bin'],
      },
    ]);
    expect(resolutions).toEqual([]);
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

  test('marks a duplicate that spreads to another unit as grown', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'], 'c/c.lib': [] });
    const head = side(interner, { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'], 'c/c.lib': ['fn f'] });

    const [regression] = compare(base, head, interner).regressions;
    expect(regression?.kind).toBe('grown');
    expect(regression?.addedUnits).toEqual(['c/c.lib']);
  });

  test('does not report a duplicate that was already there', () => {
    const interner = new Interner();
    const units = { 'a/a.lib': ['fn f'], 'b/b.lib': ['fn f'] };

    expect(compare(side(interner, units), side(interner, units), interner).regressions).toEqual([]);
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
        baseUnits: ['app/app.lib', 'schema/schema.lib'],
        headUnits: ['schema/schema.lib'],
      },
    ]);
  });

  // A crate the PR adds exists only on head, and what it duplicates counts.
  test('counts duplicates in a unit that exists only on head', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn f'] });
    const head = side(interner, { 'a/a.lib': ['fn f'], 'new/new.lib': ['fn f'] });

    const { regressions, units } = compare(base, head, interner);
    expect(regressions.map((r) => r.addedUnits)).toEqual([['new/new.lib']]);
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
  test('groups regressions by definition and escapes backticks', () => {
    const interner = new Interner();
    const base = side(interner, { 'a/a.lib': ['fn g::<u8>', 'fn g::<u16>'], 'b/b.lib': [] });
    const head = side(interner, {
      'a/a.lib': ['fn g::<u8>', 'fn g::<u16>'],
      'b/b.lib': ['fn g::<u8>', 'fn g::<u16>'],
    });

    const markdown = render(compare(base, head, interner));
    expect(markdown).toStartWith('2 items newly compiled in more than one unit (1 definitions)');
    expect(markdown).toContain('| `fn g::<…>` | 2 | `b/b.lib` |');
  });

  test('says nothing changed when nothing did', () => {
    const interner = new Interner();
    const units = { 'a/a.lib': ['fn f'] };
    expect(render(compare(side(interner, units), side(interner, units), interner))).toBe(
      '0 items newly compiled in more than one unit (0 definitions), 0 duplicates resolved.\n',
    );
  });
});
