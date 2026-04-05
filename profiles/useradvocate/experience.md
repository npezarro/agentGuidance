# User Advocate Experience Log

---
## 2026-03-30 | groceryGenius error messages
**Task:** Evaluate the user-facing error messages across groceryGenius for clarity, helpfulness, and actionability.
**What worked:** Walked through every error state in the recipe import flow as a first-time user. Found that 6 of 8 error messages were developer-facing ("500 Internal Server Error", "ECONNREFUSED", "Invalid selector: .recipe-ingredients") with no guidance for the user. Rewrote each one with the pattern: what happened (in plain language), why it might have happened, and what to try next. Example: "We couldn't read the recipe from this URL. The site may block automated access. Try pasting the recipe text directly instead."
**What didn't:** Initially categorized errors by HTTP status code (4xx vs 5xx) for the rewrite. This was developer thinking, not user thinking. Users do not care whether the error is a 404 or a 500; they care whether the problem is something they can fix (wrong URL) or something they cannot (server issue). Recategorized by user actionability instead.
**Learned:** Error messages should be categorized by user actionability, not by technical cause. The two categories that matter are: "you can fix this" (retry, correct input, try alternative) and "we need to fix this" (report it, try again later). Every error message must include at least one concrete next step. Never show raw error codes, stack traces, or internal identifiers to users.

---
## 2026-03-24 | valueSortify first-time user experience
**Task:** Walk through valueSortify as a first-time user with no prior context, identifying friction points and confusing states.
**What worked:** Identified three critical friction points: (1) the landing page showed a "Start Sorting" button with no explanation of what would happen, (2) the sorting phase presented pairs of values but did not explain the comparison method or that it would converge on a ranking, (3) the results page showed a ranked list with no explanation of how scores were calculated. Added brief contextual help text at each phase transition.
**What didn't:** Suggested adding a full onboarding tutorial with step-by-step instructions. The developer correctly pushed back: the app has only 3 phases, and a tutorial longer than the actual experience would be counterproductive. Short inline explanations at phase transitions were sufficient.
**Learned:** Onboarding should be proportional to the complexity of the experience. A 3-step app does not need a tutorial; it needs contextual microcopy at decision points. The test is: can a user complete the core flow without asking "what does this mean?" If the answer is no, add a sentence of explanation at that specific point, not a separate onboarding flow.

---
## 2026-03-19 | promptlibrary search discoverability
**Task:** Evaluate whether users can discover and effectively use the prompt library's search and filter features.
**What worked:** Tested with the "squint test": blurred the page to see what stands out visually. The search bar was visually prominent, but the category filters were hidden behind a "Filters" button that looked like a label, not a control. The tag chips used the same color as body text, making them look like labels rather than clickable filters. Recommended: make the filter button look interactive (border, icon), and use the primary color for active tag chips.
**What didn't:** Suggested adding placeholder text in the search bar like "Search prompts by keyword, category, or tag..." which was too long and got truncated on mobile. Shortened to "Search prompts..." which was sufficient. The detailed search syntax could go in a tooltip or help text, not the placeholder.
**Learned:** Interactive elements must visually communicate that they are interactive. The two most common discoverability failures are: (1) buttons that look like labels (no border, no icon, no hover state), and (2) clickable elements that use the same visual weight as static text. Use the "squint test" (blur the page) to check if interactive elements are visually distinct from content.
