# Frontend Experience Log

---
## 2026-04-06 | youtubeSpeedSetAndRemember v19.0 SPA state persistence for Shorts
**Task:** Fix Shorts speed not persisting across swipes. Previously, the MutationObserver reset speed to default on every swipe because it couldn't distinguish "new Shorts video" from "user-set speed."
**What worked:** Introduced a `sessionSpeed` module-level variable set by `setSpeed()` when on Shorts. The observer reapplies `sessionSpeed` after each swipe instead of resetting to default. Debounced the MutationObserver (250ms) to prevent rapid-fire re-injections during swipe transitions. Added mobile Shorts container selectors (`ytm-shorts-player-renderer`, `#shorts-container`) for broader swipe detection.
**What didn't:** The original approach treated every MutationObserver callback as a "new video" event requiring a speed reset. This was correct for initial page load but wrong for swipes where the user had already set a speed. Also, without debouncing, the observer fired dozens of times per swipe causing visible UI flickering.
**Learned:** In YouTube's SPA, distinguish between "session state" (survives navigation within the same page type) and "persistent state" (survives across sessions). Use module-level variables for session state and GM_setValue for persistent state. Always debounce MutationObservers watching YouTube containers; mutations come in bursts during SPA transitions.

---
## 2026-04-05 | youtubeSpeedSetAndRemember v18.0-18.2 YouTube DOM adaptation
**Task:** Fix Shorts speed toggle broken by YouTube removing `[is-active]` attribute from `ytd-reel-video-renderer`, plus add mobile Shorts support after `ytm-shorts-player-renderer` removal.
**What worked:** Defensive container detection: use `offsetHeight > 0` to filter invisible elements, `getComputedStyle` for positioning checks, and stable IDs (`#shorts-player`, `#player-container-id`) as primary selectors with class-based fallbacks. Moved Shorts toggle into `#actions` as first child to match YouTube's native action button aesthetic. Separated desktop/mobile Shorts container detection cleanly.
**What didn't:** Initially relied on `[is-active]` attribute on `ytd-reel-video-renderer` to find the current Shorts video. YouTube removed the attribute silently, breaking detection. Also relied on `ytm-player` and `ytm-shorts-player-renderer` for mobile detection, both removed in the same update cycle.
**Learned:** YouTube changes DOM structure frequently and without notice. Never rely on custom attributes or specific element tag names as sole selectors for YouTube userscripts. Always have fallback selectors targeting stable container IDs. Test both desktop and mobile paths independently, as YouTube can change them at different times.

---
## 2026-04-02 | groceryGenius recipe card redesign
**Task:** Redesign the recipe card component to show ingredient counts, prep time, and dietary tags in a compact layout.
**What worked:** Built the card as a composition of small subcomponents (RecipeImage, RecipeMeta, DietaryTags) rather than one monolithic component. Used Tailwind's `line-clamp-2` for recipe titles to prevent layout overflow. Checked the existing design tokens in tailwind.config.js and reused the existing color palette and spacing scale instead of introducing new values.
**What didn't:** Initially used CSS Grid for the card layout, which made the responsive behavior complex (needed different grid templates at 3 breakpoints). Switched to Flexbox with `flex-wrap`, which handled responsive reflow naturally without media queries.
**Learned:** For card-style components that need to reflow at different viewport widths, Flexbox with wrap is simpler than Grid with breakpoint-specific templates. Use Grid when you need explicit row/column alignment across cards; use Flexbox when cards should independently adapt their internal layout.

---
## 2026-03-27 | valueSortify drag-and-drop ranking
**Task:** Implement drag-and-drop reordering for the value ranking phase using a lightweight library.
**What worked:** Used @dnd-kit/core (6KB gzipped) instead of react-beautiful-dnd (30KB+, unmaintained). Built accessible drag handles with proper ARIA attributes (aria-roledescription="sortable", aria-grabbed). Keyboard support (space to grab, arrows to move, space to drop) came free from dnd-kit's accessibility preset.
**What didn't:** Initially tried implementing drag-and-drop from scratch using native HTML drag events. The native API does not fire drag events on touch devices without polyfills, and the drop visual feedback required manual position calculation. Abandoned after 2 hours when the touch support issues became clear.
**Learned:** Never implement drag-and-drop from scratch for production. The native HTML Drag and Drop API has fundamental gaps: no touch support, no keyboard support, poor visual feedback control. Use a library, but choose carefully by size and maintenance status. @dnd-kit is the modern replacement for react-beautiful-dnd.

---
## 2026-03-22 | botlink profile page
**Task:** Build the public bot profile page with capability badges, integration status indicators, and a contact button.
**What worked:** Semantic HTML structure: `<article>` for the profile, `<dl>` for key-value pairs (created date, platform, capabilities), `<ul>` for integration list. Used Tailwind's `group` modifier for hover states on the integration cards. Tested with browser devtools accessibility audit (Lighthouse) and fixed two color contrast issues before committing.
**What didn't:** Used `div` soup initially for the capability badges, which made the component inaccessible to screen readers. Refactored to `<ul><li>` with `role="list"` after the Lighthouse audit flagged it. Should have started with semantic HTML.
**Learned:** Start with semantic HTML elements (article, dl, ul, nav) and only reach for div when no semantic element fits. Running Lighthouse accessibility audit before committing catches issues that visual testing misses. Color contrast failures are the most common accessibility issue in dark-themed UIs.

---
## 2026-03-18 | promptlibrary search and filter UI
**Task:** Build the search bar with category filter dropdown and tag chips for the prompt library.
**What worked:** Controlled input with debounced search (300ms) using a custom useDebounce hook. Filter state stored in URL search params via Next.js useSearchParams so searches are shareable and survive page refreshes. Tag chips as toggle buttons with `aria-pressed` for accessibility.
**What didn't:** Initially stored filter state in React useState, which meant searches were lost on page refresh and users could not share filtered views. Migrating to URL search params required refactoring the data fetching to read from the URL instead of component state.
**Learned:** For any search/filter UI, store filter state in URL search params from the start, not component state. The refactoring cost of migrating from useState to URL params later is significant because it changes the data flow direction. URL-first also gives you free shareability, back-button support, and browser history.
