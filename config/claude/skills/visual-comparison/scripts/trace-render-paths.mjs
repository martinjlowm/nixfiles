#!/usr/bin/env node
// trace-render-paths.mjs — static render-path tracer for the visual-comparison skill.
//
// Uses the TARGET project's own `typescript` package (resolved from the cwd) to build a
// reverse render graph over the project's tsconfig: which components render a target
// component, behind which guards ({open && <Dialog/>}, ternaries, <Dialog open={...}>,
// <TabPanel value=...>), and which onClick handler flips the guarding state. Emits
// breadcrumb paths from route entry points (Next.js pages/ and app/ conventions) down
// to the target.
//
// Run from the root of the application under test:
//   node trace-render-paths.mjs [--project tsconfig.json] [--json] [--max-paths N] [--max-depth N] <Component|file>...
//
// Targets: PascalCase component names, or file paths (all components declared in the file).
// Output is a draft, not ground truth — dynamic component maps, render props, portals from
// unrelated trees, and non-file-based routers are not modeled; unresolved hops are marked.

import { createRequire } from 'node:module';
import path from 'node:path';
import process from 'node:process';

const USAGE = `Usage: node trace-render-paths.mjs [--project tsconfig.json] [--json] [--max-paths N] [--max-depth N] <Component|file>...
Run from the target project's root (its own typescript + tsconfig are used).`;

function die(msg) {
  console.error(msg);
  process.exit(1);
}

// ---- CLI ----
const opts = { project: undefined, json: false, maxPaths: 5, maxDepth: 12 };
const targets = [];
{
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--project') opts.project = argv[++i];
    else if (a === '--json') opts.json = true;
    else if (a === '--max-paths') opts.maxPaths = Number(argv[++i]);
    else if (a === '--max-depth') opts.maxDepth = Number(argv[++i]);
    else if (a === '-h' || a === '--help') { console.log(USAGE); process.exit(0); }
    else targets.push(a);
  }
}
if (!targets.length) die(USAGE);

// ---- Load the project's own TypeScript ----
const projectRoot = process.cwd();
let ts;
try {
  ts = createRequire(path.join(projectRoot, 'package.json'))('typescript');
} catch {
  die(`Could not resolve the project's own 'typescript' package from ${projectRoot} — run this from the target project root (after its dependencies are installed).`);
}

const configPath = opts.project
  ? path.resolve(opts.project)
  : ts.findConfigFile(projectRoot, ts.sys.fileExists, 'tsconfig.json');
if (!configPath) die('No tsconfig.json found — pass --project <path>.');
const readResult = ts.readConfigFile(configPath, ts.sys.readFile);
if (readResult.error) die(ts.flattenDiagnosticMessageText(readResult.error.messageText, '\n'));
const parsed = ts.parseJsonConfigFileContent(readResult.config, ts.sys, path.dirname(configPath));
const program = ts.createProgram({ rootNames: parsed.fileNames, options: parsed.options });
const checker = program.getTypeChecker();

const isPascal = (s) => /^[A-Z]/.test(s);
const rel = (f) => path.relative(projectRoot, f);
const projectFiles = program
  .getSourceFiles()
  .filter((sf) => !sf.fileName.includes('/node_modules/') && !sf.isDeclarationFile);

// ---- Pass 1: register components (PascalCase function/arrow/class declarations) ----
const components = new Map(); // declaration node -> { name, file, node, parents: [{parent, reveal}] }

function register(node, name, sf) {
  if (!components.has(node)) components.set(node, { name, file: sf.fileName, node, parents: [] });
}

function defaultName(sf) {
  const base = path.basename(sf.fileName).replace(/\.(t|j)sx?$/, '');
  const source = base === 'index' || base === 'page' ? path.basename(path.dirname(sf.fileName)) : base;
  return source.replace(/(^|[-_])(\w)/g, (_, __, c) => c.toUpperCase());
}

for (const sf of projectFiles) {
  const visit = (node) => {
    if (ts.isFunctionDeclaration(node) && node.name && isPascal(node.name.text)) {
      register(node, node.name.text, sf);
    } else if (
      ts.isFunctionDeclaration(node) && !node.name &&
      node.modifiers?.some((m) => m.kind === ts.SyntaxKind.DefaultKeyword)
    ) {
      register(node, defaultName(sf), sf);
    } else if (
      ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) &&
      isPascal(node.name.text) && node.initializer
    ) {
      register(node, node.name.text, sf);
    } else if (ts.isClassDeclaration(node) && node.name && isPascal(node.name.text)) {
      register(node, node.name.text, sf);
    } else if (
      ts.isExportAssignment(node) && !node.isExportEquals &&
      (ts.isArrowFunction(node.expression) || ts.isFunctionExpression(node.expression))
    ) {
      register(node, defaultName(sf), sf);
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
}

function componentForDecl(d) {
  for (let cur = d, i = 0; cur && i < 4; cur = cur.parent, i++) {
    if (components.has(cur)) return components.get(cur);
  }
  return null;
}

// ---- Reveal analysis helpers ----
const CONTAINER_RE = /(Dialog|Modal|Drawer|Popover|Popper|Menu|Collapse|Accordion|TabPanel|Sheet|Overlay)$/;
const GUARD_PROPS = ['open', 'isOpen', 'in', 'visible', 'show'];

function findAttr(el, names) {
  for (const a of el.attributes?.properties ?? []) {
    if (ts.isJsxAttribute(a) && names.includes(a.name.getText())) return a;
  }
  return null;
}

function attrExpression(attr) {
  if (!attr?.initializer) return null;
  if (ts.isJsxExpression(attr.initializer)) return attr.initializer.expression ?? null;
  return attr.initializer; // string literal
}

function attrString(el, names) {
  const expr = attrExpression(findAttr(el, names));
  return expr && ts.isStringLiteralLike(expr) ? expr.text : null;
}

function jsxTextOf(open) {
  const parent = open.parent;
  if (!parent || !ts.isJsxElement(parent)) return null;
  const txt = parent.children
    .map((ch) => {
      if (ts.isJsxText(ch)) return ch.text;
      if (ts.isJsxExpression(ch) && ch.expression && ts.isStringLiteralLike(ch.expression)) return ch.expression.text;
      return '';
    })
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
  return txt ? txt.slice(0, 40) : null;
}

function describeJsxElement(el) {
  if (!el || !el.tagName) return null;
  const label = attrString(el, ['aria-label', 'label', 'title', 'tooltip']) ?? jsxTextOf(el);
  return label ? `"${label}"` : `<${el.tagName.getText()}>`;
}

// Find the element whose on* handler calls the setter that flips `guard` truthy.
// Follows one level of named-handler indirection (const handleOpen = () => setOpen(true)).
function resolveTrigger(guard, comp) {
  let name = null;
  let expr = guard;
  if (ts.isPrefixUnaryExpression(expr) && expr.operator === ts.SyntaxKind.ExclamationToken) expr = expr.operand;
  if (ts.isIdentifier(expr)) name = expr.text;
  else if (ts.isPropertyAccessExpression(expr)) name = expr.name.text;
  if (!name) return null;
  const setter = 'set' + name[0].toUpperCase() + name.slice(1);

  let trigger = null;
  const visit = (node) => {
    if (trigger) return;
    if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === setter) {
      const arg = node.arguments[0];
      if (!arg || arg.kind !== ts.SyntaxKind.FalseKeyword) trigger = describeHandlerSite(node, comp);
    }
    ts.forEachChild(node, visit);
  };
  visit(comp.node);
  return trigger;
}

function describeHandlerSite(callNode, comp) {
  for (let cur = callNode.parent; cur && cur !== comp.node; cur = cur.parent) {
    if (ts.isJsxAttribute(cur) && cur.name.getText().startsWith('on')) {
      return describeJsxElement(cur.parent?.parent);
    }
    if (ts.isVariableDeclaration(cur) && ts.isIdentifier(cur.name)) {
      const handlerName = cur.name.text;
      let desc = null;
      const scan = (n) => {
        if (desc) return;
        if (
          ts.isJsxAttribute(n) && n.name.getText().startsWith('on') &&
          n.initializer && ts.isJsxExpression(n.initializer) &&
          n.initializer.expression?.getText().includes(handlerName)
        ) {
          desc = describeJsxElement(n.parent?.parent);
        }
        ts.forEachChild(n, scan);
      };
      scan(comp.node);
      return desc;
    }
  }
  return null;
}

// A guard referencing one of the component's own props is controlled by the parent —
// the interaction lives on the parent edge (e.g. <ExportDialog open={showExport}/>),
// so annotating it again here would only add noise.
function isParentControlled(expr, comp) {
  let e = expr;
  while (ts.isPrefixUnaryExpression(e)) e = e.operand;
  if (ts.isPropertyAccessExpression(e)) e = e.expression;
  if (!ts.isIdentifier(e)) return false;
  const sym = checker.getSymbolAtLocation(e);
  for (const d of sym?.getDeclarations() ?? []) {
    let param = null;
    for (let cur = d; cur; cur = cur.parent) {
      if (ts.isParameter(cur)) { param = cur; break; }
      if (cur === comp.node || ts.isSourceFile(cur)) break;
    }
    for (let cur = param; cur; cur = cur.parent) if (cur === comp.node) return true;
  }
  return false;
}

function guardNote(guard, comp, containerName) {
  if (isParentControlled(guard, comp)) return null;
  // Tab pattern: value === 'x' → the panel selected by that value.
  if (
    ts.isBinaryExpression(guard) &&
    (guard.operatorToken.kind === ts.SyntaxKind.EqualsEqualsEqualsToken ||
      guard.operatorToken.kind === ts.SyntaxKind.EqualsEqualsToken)
  ) {
    const lit = [guard.left, guard.right].find((e) => ts.isStringLiteralLike(e));
    if (lit) return `[tab "${lit.text}"]`;
  }
  const trigger = resolveTrigger(guard, comp);
  if (trigger) return containerName ? `[click ${trigger} → opens ${containerName}]` : `[click ${trigger}]`;
  const text = guard.getText().replace(/\s+/g, ' ').slice(0, 48);
  return `[state ${text} — trigger?]`;
}

// How is `jsxNode` (a usage of the child component inside `comp`) revealed?
function analyzeReveal(jsxNode, comp) {
  const notes = [];
  // The child's own JSX element may carry the guard prop: <ExportDialog open={showExport}/>
  const ownGuard = attrExpression(findAttr(jsxNode, GUARD_PROPS));
  if (ownGuard && !ts.isStringLiteralLike(ownGuard)) notes.push(guardNote(ownGuard, comp, jsxNode.tagName.getText()));

  let prev = jsxNode;
  for (let cur = jsxNode.parent; cur && cur !== comp.node; prev = cur, cur = cur.parent) {
    if (
      ts.isBinaryExpression(cur) &&
      cur.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken &&
      prev === cur.right
    ) {
      notes.push(guardNote(cur.left, comp));
    } else if (ts.isConditionalExpression(cur) && (prev === cur.whenTrue || prev === cur.whenFalse)) {
      notes.push(guardNote(cur.condition, comp));
    } else if (ts.isIfStatement(cur) && (prev === cur.thenStatement || prev === cur.elseStatement)) {
      notes.push(guardNote(cur.expression, comp));
    } else if (ts.isJsxElement(cur)) {
      const open = cur.openingElement;
      const tag = ts.isIdentifier(open.tagName) ? open.tagName.text : open.tagName.getText();
      if (CONTAINER_RE.test(tag)) {
        const guard = attrExpression(findAttr(open, [...GUARD_PROPS, 'value']));
        if (guard && !ts.isStringLiteralLike(guard)) notes.push(guardNote(guard, comp, tag));
        else if (guard && ts.isStringLiteralLike(guard) && tag.endsWith('TabPanel')) notes.push(`[tab "${guard.text}"]`);
        else notes.push(`[inside <${tag}>]`);
      }
    }
  }
  return [...new Set(notes.filter(Boolean))];
}

// ---- Pass 2: edges (reverse render graph) ----
for (const comp of components.values()) {
  const walk = (node) => {
    if (node !== comp.node && components.has(node)) return; // nested component boundary
    if (
      (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) &&
      ts.isIdentifier(node.tagName) && isPascal(node.tagName.text)
    ) {
      let sym = checker.getSymbolAtLocation(node.tagName);
      if (sym && sym.flags & ts.SymbolFlags.Alias) {
        try { sym = checker.getAliasedSymbol(sym); } catch { /* keep original */ }
      }
      for (const d of sym?.getDeclarations() ?? []) {
        const child = componentForDecl(d);
        if (child && child !== comp) {
          child.parents.push({ parent: comp, reveal: analyzeReveal(node, comp) });
          break;
        }
      }
    }
    ts.forEachChild(node, walk);
  };
  walk(comp.node);
}

// ---- Route mapping (Next.js pages/ and app/ conventions) ----
function routeForFile(file) {
  const f = file.replace(/\\/g, '/');
  let m = f.match(/\/pages\/(.+?)\.(t|j)sx?$/);
  if (m && !m[1].startsWith('api/') && !path.basename(m[1]).startsWith('_')) {
    return '/' + m[1].replace(/\/?index$/, '');
  }
  m = f.match(/\/app\/(.*?)page\.(t|j)sx?$/);
  if (m) {
    const segs = m[1].split('/').filter((s) => s && !s.startsWith('('));
    return '/' + segs.join('/');
  }
  return null;
}

// ---- BFS from target up to routed roots ----
const edgeScore = (e) => (e.reveal.some((n) => n.startsWith('[click') || n.startsWith('[tab')) ? 2 : e.reveal.length ? 1 : 0);

function tracePaths(target) {
  const results = [];
  const queue = [[{ comp: target, reveal: [] }]]; // leaf-first paths
  while (queue.length && results.length < opts.maxPaths) {
    const p = queue.shift();
    const head = p[p.length - 1];
    const route = routeForFile(head.comp.file);
    if (route !== null) { results.push({ route, path: p }); continue; }
    if (p.length >= opts.maxDepth) continue;
    if (!head.comp.parents.length) { results.push({ route: null, path: p }); continue; }
    const byParent = new Map(); // best-informed edge per distinct parent
    for (const e of head.comp.parents) {
      const prevBest = byParent.get(e.parent);
      if (!prevBest || edgeScore(e) > edgeScore(prevBest)) byParent.set(e.parent, e);
    }
    for (const e of byParent.values()) {
      if (p.some((s) => s.comp === e.parent)) continue; // cycle
      queue.push([...p.slice(0, -1), { comp: head.comp, reveal: e.reveal }, { comp: e.parent, reveal: [] }]);
    }
  }
  results.sort((a, b) => (a.route === null) - (b.route === null));
  return results;
}

function breadcrumb(r) {
  const steps = [...r.path].reverse(); // root-first
  const prefix = r.route !== null ? `(${r.route}) ` : `(unrouted: ${rel(steps[0].comp.file)}) `;
  return prefix + steps
    .map((s) => (s.reveal.length ? s.reveal.join(' ') + ' ' : '') + s.comp.name)
    .join(' ▸ ');
}

// ---- Resolve targets and emit ----
const targetComps = [];
for (const t of targets) {
  if (t.includes('/') || /\.(t|j)sx?$/.test(t)) {
    const abs = path.resolve(projectRoot, t);
    for (const c of components.values()) if (path.resolve(c.file) === abs) targetComps.push(c);
  } else {
    for (const c of components.values()) if (c.name === t) targetComps.push(c);
  }
}
if (!targetComps.length) die(`No components matched: ${targets.join(', ')} (targets are PascalCase names or project file paths).`);

const output = targetComps.map((c) => {
  const paths = tracePaths(c);
  const seen = new Set();
  const unique = paths.filter((r) => {
    const b = breadcrumb(r);
    if (seen.has(b)) return false;
    seen.add(b);
    return true;
  });
  return {
    target: c.name,
    file: rel(c.file),
    paths: unique.map((r) => ({
      route: r.route,
      breadcrumb: breadcrumb(r),
      hops: [...r.path].reverse().map((s) => ({ component: s.comp.name, file: rel(s.comp.file), reveal: s.reveal })),
    })),
  };
});

if (opts.json) {
  console.log(JSON.stringify({ project: configPath, targets: output }, null, 2));
} else {
  for (const t of output) {
    console.log(`== ${t.target} — ${t.file} ==`);
    if (!t.paths.length) console.log('  (no render path found — dead code, dynamic dispatch, or unmodeled router)');
    for (const p of t.paths) console.log('  ' + p.breadcrumb);
    console.log('');
  }
  const unresolved = output.flatMap((t) => t.paths).filter((p) => p.breadcrumb.includes('trigger?')).length;
  if (unresolved) console.error(`note: ${unresolved} path(s) contain unresolved triggers ([state … — trigger?]) — resolve those manually before traversal.`);
}
