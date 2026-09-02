# INNOVATIONS: simple_shaping

## What Makes This Different

### I-001: Contract-carrying shaping seams
**Problem Solved:** Shaping stacks are notoriously trust-me code; consumers cannot state what they may rely on.
**Approach:** The four deferred classes (BIDI_RESOLVER, SCRIPT_ITEMIZER, GLYPH_SHAPER, FONT_FALLBACK) carry Design-by-Contract postconditions encoding the *documented invariants of the underlying APIs themselves*: bidi levels even=LTR/odd=RTL (UAX #9); cluster maps monotone (decreasing for RTL runs — per the ScriptShape doc's own cluster example); glyph-count bounds (both Uniscribe and DirectWrite document ~1.5·n+16 buffer estimates); every input character covered by exactly one run; fallback results always render *something* (no silent drops).
**Novelty:** No surveyed stack (Uniscribe, DirectWrite, HarfBuzz, cosmic-text) expresses these as machine-checked contracts; here they are the class interface.
**Design Impact:** Contracts double as the cross-backend equivalence oracle — any two backends behind the same seam must satisfy identical postconditions.

### I-002: Emoji lifted out BEFORE the shaper (image runs as a first-class run kind)
**Problem Solved:** Color emoji is unreachable through every glyph path available to this renderer (02-LANDSCAPE), and glyph-path emoji renders differently per machine.
**Approach:** A UTS #51 segmenter converts emoji sequences to `IMAGE_RUN`s ahead of itemization; the shaper never sees them; layout treats them as fixed boxes; the paint layer blits pinned PNG assets.
**Novelty:** Toolkits bolt color-font rendering onto the glyph path; this design *removes* emoji from the glyph path entirely — turning a renderer limitation into the chat product's determinism feature (🤖 pixel-identical on every member's screen).
**Design Impact:** Run model is heterogeneous from day one (GLYPH_RUN | IMAGE_RUN), which is also the future hook for inline attachments in SW_CHAT_THREAD.

### I-003: Staged nativization with a conformance gate per seam
**Problem Solved:** "Pure-Eiffel eventually" usually means an unverifiable rewrite.
**Approach:** Each seam swaps independently (D-014); a pure-Eiffel backend is promoted only when it passes the same pinned oracle as the native one — for bidi, the full Unicode BidiTest.txt (513,494 cases) + BidiCharacterTest.txt.
**Novelty:** The replacement ladder and its promotion gates are part of the library's design artifacts, not an aspiration; mirrors the ecosystem's CNG-for-crypto precedent named in D-014.
**Design Impact:** The conformance harness is MVP scope (testing/), not future scope.

### I-004: First Eiffel text-shaping library
**Problem Solved:** No Eiffel shaping/bidi work exists (simple_*, Gobo, ISE — verified in 02).
**Approach/Novelty:** Fills a real ecosystem gap with the OS-adoption strategy rather than a port; the seam architecture is what makes an eventual pure-Eiffel core credible.
**Design Impact:** API is designed Eiffel-first (STRING_32 in, agents/queries out), not as a C wrapper's shadow.

## Differentiation from Existing Solutions

| Aspect | Existing | Our Approach | Benefit |
|--------|----------|--------------|---------|
| Pipeline decomposition | Monolithic (Uniscribe/DWrite own the whole pipeline) or two-way (Pango vs HarfBuzz) | Four independently swappable contract seams | Per-seam nativization; per-seam testing |
| Emoji | Color-font machinery (COLR/CBDT/SVG) on the glyph path | Image runs before the shaper, pinned asset set | Works on cairo 1.17.2 win32 at all; identical cross-machine rendering |
| Fallback | System-global (DWrite) or app-improvised (Uniscribe consumers) | Owned, configurable, deterministic list + probe (cosmic-text-style) | Same rendering on every member's machine |
| Verification | Vendor test suites internal | Unicode conformance harness shipped with the library; contracts as cross-backend oracle | A backend swap is provable, not hopeful |
| Distribution | HarfBuzz stacks ship DLLs | MVP ships zero DLLs (OS APIs only) + PNG assets | Runnable-folder policy holds |
