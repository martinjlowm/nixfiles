// Runs in the page through `agent-browser eval`. design-score.ts appends the
// call, `(selector, layoutClassPattern, marginSkipClassPattern)`, and reads the
// returned object.
(function probe(selector, layoutClassPattern, marginSkipClassPattern) {
  const root = document.querySelector(selector);
  if (!root) {
    return { error: `no element matches ${selector}` };
  }
  root.scrollIntoView({ block: 'start', inline: 'start' });

  const layoutClass = new RegExp(layoutClassPattern);
  const marginSkipClass = new RegExp(marginSkipClassPattern);
  const rectOf = (el) => {
    const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  };
  const describe = (el) => ({
    tag: el.tagName.toLowerCase(),
    classes: [...el.classList].filter((c) => c.startsWith('Mui')).join(' '),
    testid: el.getAttribute('data-testid') || '',
    text: (el.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 60),
    rect: rectOf(el),
  });
  // MUI components pad their own slots off the 4px grid by design (an outlined
  // input pads 16.5px), so padding and gap are an author's only on layout
  // containers and unclassed elements. An author's `sx` margin can land on any
  // component root, so margins are read everywhere but MUI's internal slots.
  const muiClasses = (el) => [...el.classList].filter((c) => c.startsWith('Mui'));
  const isAuthorLayout = (el) => {
    const mui = muiClasses(el);
    return mui.length === 0 || mui.some((c) => layoutClass.test(c));
  };
  const isAuthorMargin = (el) => !muiClasses(el).some((c) => marginSkipClass.test(c));
  const px = (value) => (value.endsWith('px') ? Number.parseFloat(value) : null);

  const spacing = [];
  const radii = [];
  const fonts = new Map();
  const inputs = [];
  for (const el of [root, ...root.querySelectorAll('*')]) {
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) {
      continue;
    }
    const style = getComputedStyle(el);
    const values = {};
    if (isAuthorLayout(el)) {
      for (const side of ['Top', 'Right', 'Bottom', 'Left']) {
        values[`padding${side}`] = px(style[`padding${side}`]);
      }
      if (style.display.includes('flex') || style.display.includes('grid')) {
        values.rowGap = px(style.rowGap);
        values.columnGap = px(style.columnGap);
      }
    }
    if (isAuthorMargin(el)) {
      for (const side of ['Top', 'Right', 'Bottom', 'Left']) {
        values[`margin${side}`] = px(style[`margin${side}`]);
      }
    }
    if (Object.keys(values).length > 0) {
      spacing.push({ ...describe(el), values });
    }
    if (el.classList.contains('MuiPaper-rounded') || el.classList.contains('MuiCard-root')) {
      radii.push({ ...describe(el), radius: px(style.borderTopLeftRadius) });
    }
    if (el.classList.contains('MuiOutlinedInput-root') || el.classList.contains('MuiFilledInput-root')) {
      inputs.push({
        ...describe(el),
        variant: el.classList.contains('MuiOutlinedInput-root') ? 'outlined' : 'filled',
        inDataGrid: Boolean(el.closest('.MuiDataGrid-root')),
      });
    }
    const ownText = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
    if (ownText) {
      const family = style.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '');
      const entry = fonts.get(family) || { family, count: 0, sample: describe(el) };
      entry.count++;
      fonts.set(family, entry);
    }
  }

  return {
    devicePixelRatio: window.devicePixelRatio,
    viewport: { width: window.innerWidth, height: window.innerHeight },
    root: describe(root),
    spacing,
    radii,
    inputs,
    fonts: [...fonts.values()],
  };
})
