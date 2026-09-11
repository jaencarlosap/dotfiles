---
name: landing-page
description: Use when building or redesigning a landing page, marketing site, hero section or "the site for my product" — and when asked to make one look modern, current or 2026. Covers the section order that converts, the type scale and 2026 font picks, OKLCH color and dark mode tokens, the three aesthetic lanes (techno-futurist / editorial / anti-grid), bento and blueprint-grid layout, motion that ships, the Core Web Vitals budget, a11y, AI-readability, and the anti-slop checklist. Not for app UI or dashboards. Triggers in Spanish too: "landing", "landing page", "pagina de aterrizaje", "web de mi producto", "seccion hero", "que se vea moderna", "diseño 2026".
---

# Landing page

The failure mode here is not a bug. It is a page that **looks like every other
page a model has ever generated**: indigo→violet diagonal gradient, three glassy
cards with emoji icons, "Elevate your workflow with AI-powered solutions", a
stock illustration of people pointing at a laptop, and a purple button.

That page is instantly recognisable as machine-made, and it converts badly for
the same reason: it says nothing specific about anything.

Everything below is a decision to make on purpose. Make each one, or state that
you are defaulting.

## 0. Six answers before any markup

If you cannot answer these, the page cannot be good — ask, or write the answer
you are assuming at the top of your reply and build against it.

1. **Who** lands here, coming from where (ad, launch post, docs, cold search)?
2. **One action.** What single thing should they do? Everything else is a
   distraction with a hex code.
3. **Proof.** Logos, numbers, quotes, users, funding, benchmarks — what is
   actually true and nameable? "Trusted by teams" is not proof.
4. **The visual.** Is there a real product to show — a screenshot, a recording,
   an embeddable demo? If not, the page must lean editorial (type + copy), not
   product-shot.
5. **Voice.** Serious infra, playful consumer, or editorial/premium. This picks
   the aesthetic lane in §5.
6. **Constraints.** Stack, existing brand tokens, CMS, deadline, does it have to
   be static.

## 1. Structure — the order, and the numbers behind it

Canonical order, top to bottom:

```
nav (minimal)  →  hero  →  social proof strip  →  problem  →  solution/how it
works  →  features (bento)  →  proof again (case/testimonial/metric)  →
pricing  →  FAQ  →  final CTA  →  lean footer
```

Optional, and only when you have a real reason: comparison-vs-alternatives
table (you have a named competitor objection), founder/team section (trust is
the blocker), integrations grid, security/compliance strip.

Measured behaviour worth designing against:

- Median landing page conversion is **6.6%** across industries (Unbounce, 464M
  visits / 41k pages); B2B sits near 3.6%, SaaS free-trial near 7.2%.
- Attention above the fold: **~11s desktop, ~7s mobile.** The headline, the
  proof and the button have to land inside that.
- Short page, simple offer: **one CTA above the fold converts ~17% better**.
  Long page, complex offer: **CTAs repeated through the page, ~23% better**.
- **Sticky bottom CTA alone: +11%.** Above-fold alone: +6%. Both together: only
  +12% — they do not compound, so do not clutter.
- **Social proof inside the first viewport: +12%.** And specificity wins —
  "Trusted by 8 of the Fortune 50" beat a plain logo strip by 14 points.

Rules that follow: one offer per page, one primary CTA repeated (same words,
same colour, every time), nav stripped to logo + 1–2 links + the CTA, no
carousel, no hamburger hiding the only button on mobile.

## 2. Hero

Four things, nothing else:

- **Headline (≤10 words): the outcome, plus who it is for.** Not the product
  category. "Ship your Postgres schema changes without downtime" beats
  "The modern database platform".
- **Subhead (≤25 words):** what it literally is, for whom, and the mechanism.
  This is where the plain noun lives ("a CLI and a hosted runner that…").
- **One visual that IS the product.** Real screenshot, a 6–12s silent looping
  screen recording, or an embedded interactive demo. Interactive demos are the
  single strongest 2026 pattern — real product visuals beat illustrations and
  3D consistently; abstract blobs are decoration.
- **One primary CTA** + at most one ghost secondary ("See how it works" →
  anchor). Under it, one line of risk-removal microcopy: "Free tier, no card",
  "Deploy in 2 minutes".

Two formulas cover almost every hero. **PAS** (problem → agitate → solution)
when the pain is felt and named. **BAB** (before → after → bridge) when the pain
is ambient and you have to show the after.

Kill on sight: "Elevate", "Unlock", "Seamless", "Revolutionize", "Empower",
"Take your X to the next level", "AI-powered solutions", and any headline that
would still be true if you swapped in a competitor's name.

## 3. Typography — the actual system

Type is where a modern page is won. The 2026 signal is **large, confident
display type with tight tracking, against small, quiet, very readable body
text** — plus a return of serifs and italics for display.

**Scale.** Fluid, not a pile of breakpoints. A 1.25 ratio for UI, 1.333 for
editorial:

```css
:root {
  --step--1: clamp(0.83rem, 0.8rem + 0.15vw, 0.9rem);
  --step-0:  clamp(1rem, 0.96rem + 0.2vw, 1.125rem);   /* body */
  --step-1:  clamp(1.25rem, 1.15rem + 0.5vw, 1.5rem);
  --step-2:  clamp(1.6rem, 1.4rem + 1vw, 2.25rem);
  --step-3:  clamp(2rem, 1.6rem + 2vw, 3.5rem);
  --step-4:  clamp(2.6rem, 1.8rem + 4vw, 5.5rem);      /* hero display */
}
```

**Rules that matter more than the font choice:**

- Body **16–18px minimum**, line-height 1.5–1.65, measure **60–75ch**
  (`max-width: 65ch`). Long full-width paragraphs are the most common tell of a
  page nobody designed.
- Display sizes get **negative tracking** (`letter-spacing: -0.02em` at 3rem,
  `-0.03em` above 4rem) and line-height 0.95–1.1. Body gets 0.
- `text-wrap: balance` on headings, `text-wrap: pretty` on paragraphs — Baseline
  now, and it removes the orphaned last word that makes a hero look amateur.
- Two families maximum, three only if mono is a third. A weight range is not a
  second family.
- Uppercase only for eyebrow labels, at ≤13px with `+0.08em` tracking.

**Fonts that read as current in 2026** (all variable, all self-hostable):

| Role | Picks |
| --- | --- |
| UI / neutral sans | Inter, Geist, Mona Sans, Figtree, Manrope |
| Warmer / geometric sans | Satoshi, General Sans, Switzer |
| Display serif (the 2026 move) | Instrument Serif, Fraunces (variable optical + `SOFT`/`WONK`), Newsreader, Playfair Display |
| Mono (dev-facing, or as accent) | JetBrains Mono, Geist Mono, IBM Plex Mono |

Pairings that work: **neutral sans body + display serif headings** (editorial,
premium, currently everywhere); **one sans, two weights, huge contrast** (300
body vs 700 display — the Linear/Vercel read); **mono eyebrow + sans everything**
(dev tools). Two similar sans families is the one pairing to avoid — it reads as
a mistake, not a decision.

**Loading, or the type ruins CLS and LCP:**

```html
<link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin>
```

Self-host `woff2` (subset to latin), `font-display: swap`, and set a fallback
with `size-adjust`/`ascent-override` so the swap does not shift the hero. Never
`@import` a Google Fonts CSS file in the critical path.

## 4. Color

**Work in OKLCH.** It is perceptually uniform, so a ramp built by moving L stays
even, and interpolation between two brand colors does not go grey/muddy in the
middle. Tailwind v4's whole palette is OKLCH already.

**3–5 colors total:** one brand, one accent (used almost nowhere, which is what
makes it an accent), two neutrals — and a semantic set for success/warn/danger.
Everything else is the neutral ramp at different lightness.

```css
:root {
  color-scheme: light dark;

  --brand:  oklch(0.62 0.19 255);          /* pick a real hue, not #6366F1 */
  --accent: oklch(0.78 0.17 85);
  --bg:     light-dark(oklch(0.99 0.004 260), oklch(0.17 0.012 260));
  --surface:light-dark(oklch(0.97 0.006 260), oklch(0.21 0.014 260));
  --text:   light-dark(oklch(0.21 0.02 260), oklch(0.96 0.008 260));
  --muted:  light-dark(oklch(0.52 0.02 260), oklch(0.72 0.015 260));
  --line:   color-mix(in oklch, var(--text) 12%, transparent);

  --radius: 0.75rem;   /* 8–16px reads current; 24px+ reads 2021 */
}
```

Notes from what is actually shipping:

- **Dark mode is expected, and is a designed palette, not an inversion.** The
  backgrounds in use are near-black blue `#0D1117`, slate `#0F172A`, zinc
  `#18181B`, warm grey `#1A1A2E`. Pure `#000` only for OLED-brand looks; pure
  `#fff` text on pure black is harsh — use ~`oklch(0.96 …)`.
- **Gradients are ambient, not rainbow.** Layered soft glow behind a hero, mesh
  gradients, a single hue drifting through lightness. A two-stop 45° purple-to-
  pink gradient across a button is the single loudest slop signal.
- Light-mode counterpart trend: warm off-whites and creams (Pantone's 2026 color
  is Cloud Dancer, a soft white) with a serif — the "editorial" lane.
- Blue-greens/teals are the ascending hue if you need a fresh brand color.
- Hairlines beat shadows for structure: `1px solid var(--line)` plus one soft
  shadow, not four blurry ones.
- `contrast-color()` and `color-mix()` are Baseline — use them instead of
  hardcoding a second text color per surface.

## 5. Pick ONE aesthetic lane and commit

Mixing these is what makes a page feel assembled from tutorials.

**A. Techno-futurist** (Linear, Vercel, Stripe, most dev tools). Dark by
default, blueprint grid or dotted background behind the hero, GPU-ish gradient
glow, fine 1px borders, bento grids, product UI floating with a subtle border +
soft shadow, mono accents, very tight display tracking. Restraint is the whole
trick: one glow, one accent, everything else neutral.

**B. Editorial / premium** (agencies, fintech, consumer, "we have taste").
Cream or off-white ground, big display serif, real photography, generous
whitespace (`section { padding-block: clamp(4rem, 10vw, 9rem) }`), asymmetric
two-column layouts, small caps eyebrows, almost no boxes.

**C. Anti-grid / brutalist** (indie, launch pages, dev-tooling counterculture —
The Browser Company, v0-adjacent). Monospace, raw borders, deliberately broken
alignment, system-ish colors, no gradients. Powerful only when everyone in the
category looks like lane A, and only if the copy is equally confident.

**Layout components that are current, and how to not get them wrong:**

- **Bento grid** for features — modular cards of unequal size, each one a
  complete idea (icon/visual + 3-word title + one sentence). Measured ~23% more
  scroll depth than a plain 12-column list. It fails when every cell is the same
  size, which is just a grid.
- **Split screen** for problem-vs-solution, before/after, two personas.
- **Sticky scroll**: copy column pinned while visuals change. Great for "how it
  works", terrible for anything the user needs to skim.
- **Logo marquee**: only with logos anyone recognises; otherwise use one
  specific number instead.
- **Glassmorphism** survives in nav bars, modals and small cards — *not* over a
  hero. `backdrop-filter: blur()` costs **15–30% FPS on mid-tier Android**.
- **3D / WebGL / Spline**: a single scene is **800KB–2MB of JS runtime** and it
  takes Core Web Vitals with it. Skip unless the brand *is* the experience.

## 6. Motion — the little that earns its place

Motion in 2026 is micro and functional: it shows how the product behaves and it
gets out of the way.

- Entrance reveals: `opacity 0→1` + `translateY 8–24px`, **200–400ms**,
  `cubic-bezier(0.16, 1, 0.3, 1)`, stagger 40–80ms. Once, on first view.
- **Prefer CSS scroll-driven animations** (`animation-timeline: view()`) — they
  run off the main thread and now ship in Chrome and Safari; they replace AOS
  and most ScrollTrigger work.
- In React, **Motion** (`motion/react`) with a parent `staggerChildren` variant
  beats hand-managed delays. GSAP + Lenis only for a genuinely cinematic brand
  page, and then budget for it.
- Animate **only** `transform` and `opacity`. Never `height`, `top`, `width`.
- Hover states are motion too: a 150ms lift/border-brighten on cards and CTAs is
  most of the perceived polish.
- **No scroll-jacking**, no autoplaying audio, no 3s intro animation gating the
  headline.
- Non-negotiable:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

## 7. Performance budget — a slow landing page is a broken landing page

Targets, at the 75th percentile of real users: **LCP < 2.5s, INP < 200ms
(43% of sites fail this one), CLS < 0.1.**

- The LCP element is almost always the hero heading or hero image. Do not lazy-
  load it; `fetchpriority="high"`, preload it, inline the critical CSS for the
  first viewport.
- Every `<img>`: explicit `width`/`height` or `aspect-ratio`, AVIF/WebP with a
  fallback, `loading="lazy"` for everything **below** the fold, `decoding="async"`.
- Video hero: `muted playsinline preload="metadata"` + a poster; never autoplay
  a 10MB mp4. A 300KB looping AVIF/WebM often beats it.
- Third parties are the usual killer: analytics, chat widget, cookie banner,
  4 fonts. Load chat on interaction, defer analytics, budget ~150KB of JS for a
  marketing page.
- Ship real HTML — SSR/SSG. A page whose text only exists after hydration loses
  both the LCP and the AI crawler (§9).
- Verify, do not assume: run Lighthouse (the `chrome-devtools` skill) on the
  built page, throttled, mobile.

## 8. Accessibility (also: it is the same list as "looks professional")

- Contrast **4.5:1** body, **3:1** large text and UI borders — *check dark mode
  separately*, that is where it fails.
- Visible `:focus-visible` ring on every interactive element; never
  `outline: none` without a replacement.
- Tap targets ≥44px (WCAG 2.2 minimum is 24px — aim for 44).
- One `h1`, headings in order, sections labelled, `<button>` for actions and
  `<a>` for navigation.
- Alt text that says what the screenshot shows, not "hero image".
- The page must work at **390px wide** and at **200% zoom**. Test both.
- Never put the headline inside an image or a canvas.

## 9. AI readability — the layer that got added in 2026

A meaningful share of arrivals now come through ChatGPT, Perplexity, Google AI
Overviews and Copilot, which cite a handful of sources per answer. To be
citable:

- **Server-render real text.** Crawlers do not run your shader.
- **JSON-LD**: `Organization`, `SoftwareApplication`/`Product`, `FAQPage`,
  `BreadcrumbList`. Structured data is not required for AI Overviews, but it is
  cheap and it disambiguates who you are.
- **Answer-first passages.** Question-shaped `h2`s ("How much does X cost?")
  followed immediately by a self-contained answer paragraph. Retrieval works at
  passage level — a paragraph that only makes sense after the previous three
  will not be quoted.
- **Give it something quotable**: concrete numbers, named integrations, a
  pricing figure, a customer quote with a name and a company.
- Meta: title, description, `og:image` (1200×630, with text that survives being
  cropped), canonical, sitemap.
- `llms.txt` is a proposed convention, not a standard — Google explicitly calls
  it unnecessary. It is ~10 lines, so add it if asked; never sell it as a
  ranking factor.

## 10. Copy rules (you will be writing it)

- Specific beats clever. Numbers beat adjectives. Nouns beat abstractions.
- Every feature card: **what it does → what that means for them.** Two lines.
- Write button labels as the user's intent: "Start free trial", "Get the
  template", "Talk to an engineer" — never "Submit", "Learn more", "Click here".
- FAQ answers the objection that stops the sale (price, migration, lock-in,
  security, "do I need to rewrite anything"), not trivia.
- If a sentence could appear on a competitor's page unchanged, delete it.

## 11. Stack defaults

- **Content-only marketing page** → Astro, or plain HTML + CSS. Both are
  legitimately the fastest and often the better answer; do not pull in React to
  render six sections.
- **Inside an existing product repo** → Next.js App Router + **Tailwind v4**
  (theme tokens live in CSS under `@theme`, palette is OKLCH) + shadcn/ui for
  primitives + **Motion** for animation. This is the stack the ecosystem and the
  component libraries assume in 2026.
- Do not add a component library, an animation library and an icon set for a
  page with four sections. Modern CSS covers most of it: container queries,
  `:has()`, `@scope`, `light-dark()`, `color-mix()`, `text-wrap`, subgrid,
  `field-sizing`, view transitions.
- Follow the repo's existing conventions over anything in this list — check
  before introducing a dependency (`dependencies` skill).

## 12. Anti-slop checklist — do not ship if any is true

- [ ] Indigo/violet diagonal gradient on the button or the hero background.
- [ ] Three equal cards with emoji icons.
- [ ] Headline that names no outcome and no audience.
- [ ] Stock illustration or abstract 3D blob instead of the product.
- [ ] Lorem ipsum, `#`-href buttons, or a fake testimonial with a fake name.
- [ ] Placeholder logos in the "trusted by" strip.
- [ ] More than two fonts, or body text under 16px.
- [ ] Full-width paragraphs running past ~75 characters.
- [ ] Same-size everything: no size contrast between display and body.
- [ ] Nav with 8 links and no CTA.
- [ ] Dark mode that is just `filter: invert()` or that was never opened.
- [ ] Animation with no `prefers-reduced-motion` fallback.
- [ ] Never opened at 390px.

## 13. Before you say it is done

```bash
# build it, serve it, look at it — do not review your own markup from memory
<build cmd> && <serve cmd>
```

Then, actually check: 390px and 1440px; light and dark; keyboard-only tab pass;
reduced-motion on; Lighthouse mobile (LCP/INP/CLS against §7); every link and
button goes somewhere real. Report what you verified and what you did not — an
unverified page is `stop-and-verify` territory, not a "done".
