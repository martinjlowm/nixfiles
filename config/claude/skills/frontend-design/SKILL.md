---
name: frontend-design
description: Design a distinctive new frontend (standalone page, landing page, prototype, demo) with a deliberate aesthetic. Use when the look is not set by an existing app.
---

**Inside an existing application, follow its design system.** Its components, tokens, fonts,
spacing and patterns win over everything below; this skill is for interfaces whose look is
yours to choose.

The user gives the requirements: a component, page or application, maybe with its purpose,
audience or technical constraints. Build working code with a clear aesthetic point of view.

## Design thinking

Before coding, settle:

- **Purpose.** What problem the interface solves, and for whom.
- **Tone.** Pick one direction and commit to it: brutally minimal, maximalist, retro-futuristic,
  organic, luxury, playful, editorial, brutalist, art deco, soft pastel, industrial, or one of
  your own.
- **Constraints.** Framework, performance, accessibility.
- **Differentiation.** The one thing someone will remember about it.

Bold maximalism and refined minimalism both work. What matters is that the choice is
deliberate and executed precisely. Maximalist designs need elaborate code and animation;
minimal ones need restraint and exact spacing and type.

## Aesthetics

- **Typography.** Distinctive, characterful fonts rather than Arial, Inter or system
  defaults. Pair a display font with a refined body font.
- **Colour.** A cohesive palette in CSS variables. Dominant colours with sharp accents beat
  timid, evenly spread ones.
- **Motion.** CSS-only for plain HTML, the Motion library for React when available. One
  orchestrated page load with staggered reveals (`animation-delay`) does more than scattered
  micro-interactions. Scroll-triggered and hover states that surprise.
- **Composition.** Asymmetry, overlap, diagonal flow, grid-breaking elements, and either
  generous negative space or controlled density.
- **Backgrounds and detail.** Atmosphere instead of flat colour: gradient meshes, noise,
  geometric patterns, layered transparency, dramatic shadows, decorative borders, grain.

Avoid the generic look: overused fonts, the theme default, purple gradients on white,
predictable layouts and cookie-cutter components. Vary between light and dark, fonts and
aesthetics from one design to the next rather than converging on the same choices (Space
Grotesk, for example).
