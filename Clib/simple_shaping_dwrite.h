/*
 * simple_shaping_dwrite.h - the PRODUCTION DirectWrite + GDI C shim for
 *                           simple_shaping (Phase 4, Task 1).
 *
 * PROVENANCE:
 *   Grown from spikes/dwrite/Clib/dwrite_spike.h (spike verdict PASS - see
 *   spikes/dwrite/run_output.txt for the measured facts this shim must
 *   reproduce). The spike is EVIDENCE and stays byte-identical; this file is
 *   its production descendant. Differences from the spike, all deliberate:
 *     - `ssd_' prefix instead of `spk_' (two distinct translation units may
 *       coexist in one build tree without colliding).
 *     - Every buffer is HEAP allocated and grows on demand; the spike's
 *       fixed SPK_MAX_TEXT / SPK_MAX_RUNS / SPK_MAX_GLYPHS caps would have
 *       silently truncated a real chat line.
 *     - The event log is gone (it was spike instrumentation).
 *     - AnalyzeLineBreakpoints (analyzer vtable slot 6) is TYPED and its sink
 *       (SetLineBreakpoints) is REAL - the spike's spk_sink_breaks was a stub.
 *       SCRIPT_ITEMIZER.soft_breaks (Task 4) consumes it.
 *     - Contract-enforcing checks in C: a "success" that leaves a run table
 *       or the glyph table empty is converted to a FAILURE here, so
 *       DWRITE_API's `runs_on_success' / `glyphs_on_success' postconditions
 *       (Phase 2 ISSUE 11) cannot be violated from the native side.
 *
 * WHY PLAIN C AND HAND-DECLARED INTERFACES:
 *   The Windows SDK's dwrite.h is C++-only: every interface is declared as
 *   `interface DWRITE_DECLARE_INTERFACE("...") IFoo : public IUnknown' with no
 *   CINTERFACE / C-vtable branch (unlike d3d11.h). Eiffel inline-C bodies are
 *   compiled as C by finish_freezing, so including dwrite.h is not an option.
 *   Instead this header declares, in C, ONLY the slices of the DirectWrite ABI
 *   simple_shaping touches: vtable structs whose slot ORDER is transcribed
 *   verbatim from the installed SDK header (method order = vtable order;
 *   unused slots are held by `void*' members so the layout stays exact). COM's
 *   binary contract (this-pointer + vtable of __stdcall function pointers) is
 *   what makes this legal; MSVC C and C++ share that ABI on x64.
 *
 * SINGLE TRANSLATION UNIT:
 *   Everything here is `static'. ALL `C inline use "simple_shaping_dwrite.h"'
 *   externals must therefore live in ONE Eiffel class (DWRITE_API) so they
 *   land in one generated .c file and share this state. GDI32_API's externals
 *   are plain Win32 calls over <windows.h> and bind directly - they hold no
 *   state and are deliberately NOT routed through this header.
 *
 * LINKING (NFR-004: zero new DLLs):
 *   dwrite.dll is loaded with LoadLibraryW + GetProcAddress
 *   ("DWriteCreateFactory") - no dwrite import library on any toolchain
 *   config. gdi32 comes in via `#pragma comment(lib, "gdi32.lib")'.
 *
 * NEVER-RAISES (NFR-011):
 *   Every HRESULT is checked here. A failure returns 0 (or NULL) with
 *   `ssd_hr' holding the real HRESULT, and the affected table reset to empty -
 *   never a partly-filled table, never an exception across the boundary.
 *
 * COM OBJECTS:
 *   - SSD_SOURCE implements IDWriteTextAnalysisSource {688e1a58-5094-47c8-adc8-fbcea60ae92b}
 *   - SSD_SINK   implements IDWriteTextAnalysisSink   {5810cd44-0ca0-4701-b3fa-bec5182ae4f6}
 *   Both are static-lifetime singletons: AddRef/Release keep no real count and
 *   never free (valid COM for objects the caller owns and outlives the calls).
 *   The spike proved every callback arrives synchronously on the calling
 *   thread (DR-012 confinement).
 *
 * Copyright (c) 2026 Larry Rix - MIT License
 */

#ifndef SIMPLE_SHAPING_DWRITE_H
#define SIMPLE_SHAPING_DWRITE_H

#include <windows.h>
#include <stdlib.h>
#include <string.h>

#if defined(_MSC_VER)
#pragma comment(lib, "gdi32.lib")
#endif

/* ================= HRESULTs reported through ssd_hr ====================== */
/* Held as unsigned long because DWRITE_API.last_hresult is a NATURAL_32. */

#define SSD_HR_OK                 0x00000000UL
#define SSD_HR_FAIL               0x80004005UL   /* E_FAIL                    */
#define SSD_HR_INVALIDARG         0x80070057UL   /* E_INVALIDARG              */
#define SSD_HR_OUTOFMEMORY        0x8007000EUL   /* E_OUTOFMEMORY             */
#define SSD_HR_MOD_NOT_FOUND      0x8007007EUL   /* ERROR_MOD_NOT_FOUND       */
#define SSD_HR_PROC_NOT_FOUND     0x8007007FUL   /* ERROR_PROC_NOT_FOUND      */
#define SSD_HR_INSUFFICIENT_BUF   0x8007007AUL   /* ERROR_INSUFFICIENT_BUFFER */

/* ================= IIDs (hand-defined; no uuid.lib dependency) ============ */

static const GUID ssd_iid_iunknown =
    {0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID ssd_iid_idwritefactory =            /* b859ee5a-d838-4b5b-a2e8-1adc7d93db48 */
    {0xb859ee5a, 0xd838, 0x4b5b, {0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48}};
static const GUID ssd_iid_analysis_source =           /* 688e1a58-5094-47c8-adc8-fbcea60ae92b */
    {0x688e1a58, 0x5094, 0x47c8, {0xad, 0xc8, 0xfb, 0xce, 0xa6, 0x0a, 0xe9, 0x2b}};
static const GUID ssd_iid_analysis_sink =             /* 5810cd44-0ca0-4701-b3fa-bec5182ae4f6 */
    {0x5810cd44, 0x0ca0, 0x4701, {0xb3, 0xfa, 0xbe, 0xc5, 0x18, 0x2a, 0xe4, 0xf6}};

static const WCHAR ssd_locale[] = L"en-us";

static int ssd_guid_eq(const GUID *a, const GUID *b) {
    return memcmp(a, b, sizeof(GUID)) == 0;
}

/* ================= DirectWrite POD types (ABI-exact) ====================== */

/* DWRITE_SCRIPT_ANALYSIS: UINT16 script; DWRITE_SCRIPT_SHAPES shapes (enum=int).
   MSVC lays this out as {u16, 2 pad, i32} in both C and C++. SCRIPT_ITEM
   carries these 8 bytes VERBATIM from the itemizer to the shaper. */
typedef struct {
    UINT16 script;
    int    shapes;
} SSD_SCRIPT_ANALYSIS;

/* DWRITE_SHAPING_TEXT_PROPERTIES / _GLYPH_PROPERTIES are UINT16 bitfield
   structs whose fields simple_shaping never reads, so an opaque UINT16 with
   the same size/alignment stands in. */
typedef struct { UINT16 bits; } SSD_TEXT_PROPS;
typedef struct { UINT16 bits; } SSD_GLYPH_PROPS;

typedef struct {
    FLOAT advanceOffset;
    FLOAT ascenderOffset;
} SSD_GLYPH_OFFSET;                                   /* DWRITE_GLYPH_OFFSET */

/* DWRITE_LINE_BREAKPOINT is one UINT8 of bitfields, allocated from the LSB by
   MSVC:  bits 0-1 breakConditionBefore, bits 2-3 breakConditionAfter,
          bit 4 isWhitespace, bit 5 isSoftHyphen, bits 6-7 padding.
   DWRITE_BREAK_CONDITION: 0 NEUTRAL, 1 CAN_BREAK, 2 MAY_NOT_BREAK, 3 MUST_BREAK. */

/* ================= Shim state (all heap, all growable) ==================== */

static unsigned long ssd_hr = SSD_HR_OK;              /* last HRESULT seen    */
static int           ssd_oom = 0;                     /* a sink hit OOM       */

static WCHAR  *ssd_text = NULL;                       /* analyzed UTF-16 text */
static UINT32  ssd_text_cap = 0;
static UINT32  ssd_text_len = 0;

typedef struct { UINT32 pos, len; SSD_SCRIPT_ANALYSIS sa; } SSD_SRUN;
static SSD_SRUN *ssd_sruns = NULL;
static int       ssd_srun_cap = 0;
static int       ssd_srun_n = 0;

typedef struct { UINT32 pos, len; UINT8 lexp, lres; } SSD_BRUN;
static SSD_BRUN *ssd_bruns = NULL;
static int       ssd_brun_cap = 0;
static int       ssd_brun_n = 0;

static UINT8  *ssd_breaks = NULL;                     /* DWRITE_LINE_BREAKPOINT bytes */
static UINT32  ssd_break_cap = 0;
static UINT32  ssd_break_n = 0;

static UINT16         *ssd_clusters = NULL;           /* sized by run length  */
static SSD_TEXT_PROPS *ssd_text_props = NULL;
static UINT32          ssd_run_cap = 0;

static UINT16          *ssd_glyphs = NULL;            /* sized by glyph count */
static FLOAT           *ssd_advances = NULL;
static SSD_GLYPH_OFFSET *ssd_offsets = NULL;
static SSD_GLYPH_PROPS *ssd_glyph_props = NULL;
static UINT32           ssd_glyph_cap = 0;
static int              ssd_glyph_n = 0;
static int              ssd_shaped_len = 0;

/* ================= Growth helpers (0 = out of memory) ===================== */

static int ssd_reserve_text(UINT32 need) {
    WCHAR *q;
    UINT32 c;
    if (ssd_text_cap >= need) return 1;
    c = ssd_text_cap ? ssd_text_cap : 64u;
    while (c < need) { if (c > 0x08000000u) return 0; c *= 2u; }
    q = (WCHAR*)realloc(ssd_text, (size_t)c * sizeof(WCHAR));
    if (!q) return 0;
    ssd_text = q;
    ssd_text_cap = c;
    return 1;
}

static int ssd_reserve_sruns(int need) {
    SSD_SRUN *q;
    int c;
    if (ssd_srun_cap >= need) return 1;
    c = ssd_srun_cap ? ssd_srun_cap : 16;
    while (c < need) { if (c > 0x02000000) return 0; c *= 2; }
    q = (SSD_SRUN*)realloc(ssd_sruns, (size_t)c * sizeof(SSD_SRUN));
    if (!q) return 0;
    ssd_sruns = q;
    ssd_srun_cap = c;
    return 1;
}

static int ssd_reserve_bruns(int need) {
    SSD_BRUN *q;
    int c;
    if (ssd_brun_cap >= need) return 1;
    c = ssd_brun_cap ? ssd_brun_cap : 16;
    while (c < need) { if (c > 0x02000000) return 0; c *= 2; }
    q = (SSD_BRUN*)realloc(ssd_bruns, (size_t)c * sizeof(SSD_BRUN));
    if (!q) return 0;
    ssd_bruns = q;
    ssd_brun_cap = c;
    return 1;
}

static int ssd_reserve_breaks(UINT32 need) {
    UINT8 *q;
    UINT32 c;
    if (ssd_break_cap >= need) return 1;
    c = ssd_break_cap ? ssd_break_cap : 64u;
    while (c < need) { if (c > 0x08000000u) return 0; c *= 2u; }
    q = (UINT8*)realloc(ssd_breaks, (size_t)c);
    if (!q) return 0;
    ssd_breaks = q;
    ssd_break_cap = c;
    return 1;
}

/* clusterMap and textProps are both indexed by CHARACTER (UTF-16 unit). */
static int ssd_reserve_run_arrays(UINT32 need) {
    UINT16 *cm;
    SSD_TEXT_PROPS *tp;
    UINT32 c;
    if (ssd_run_cap >= need) return 1;
    c = ssd_run_cap ? ssd_run_cap : 64u;
    while (c < need) { if (c > 0x08000000u) return 0; c *= 2u; }
    cm = (UINT16*)realloc(ssd_clusters, (size_t)c * sizeof(UINT16));
    if (!cm) return 0;
    ssd_clusters = cm;
    tp = (SSD_TEXT_PROPS*)realloc(ssd_text_props, (size_t)c * sizeof(SSD_TEXT_PROPS));
    if (!tp) return 0;
    ssd_text_props = tp;
    ssd_run_cap = c;
    return 1;
}

/* glyphIndices, glyphProps, advances and offsets are indexed by GLYPH. */
static int ssd_reserve_glyph_arrays(UINT32 need) {
    UINT16 *gi;
    SSD_GLYPH_PROPS *gp;
    FLOAT *ad;
    SSD_GLYPH_OFFSET *of;
    UINT32 c;
    if (ssd_glyph_cap >= need) return 1;
    c = ssd_glyph_cap ? ssd_glyph_cap : 64u;
    while (c < need) { if (c > 0x04000000u) return 0; c *= 2u; }
    gi = (UINT16*)realloc(ssd_glyphs, (size_t)c * sizeof(UINT16));
    if (!gi) return 0;
    ssd_glyphs = gi;
    gp = (SSD_GLYPH_PROPS*)realloc(ssd_glyph_props, (size_t)c * sizeof(SSD_GLYPH_PROPS));
    if (!gp) return 0;
    ssd_glyph_props = gp;
    ad = (FLOAT*)realloc(ssd_advances, (size_t)c * sizeof(FLOAT));
    if (!ad) return 0;
    ssd_advances = ad;
    of = (SSD_GLYPH_OFFSET*)realloc(ssd_offsets, (size_t)c * sizeof(SSD_GLYPH_OFFSET));
    if (!of) return 0;
    ssd_offsets = of;
    ssd_glyph_cap = c;
    return 1;
}

/* ================= SSD_SOURCE : IDWriteTextAnalysisSource ================= */
/* Vtable order per SDK dwrite.h: IUnknown(3) + GetTextAtPosition,
   GetTextBeforePosition, GetParagraphReadingDirection, GetLocaleName,
   GetNumberSubstitution. NOTE the asymmetric parameter orders (string-then-
   length vs length-then-string) - transcribed exactly. */

typedef struct SSD_SOURCE SSD_SOURCE;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_SOURCE *self, const GUID *riid, void **ppv);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_SOURCE *self);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_SOURCE *self);
    HRESULT (STDMETHODCALLTYPE *GetTextAtPosition)(SSD_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len);
    HRESULT (STDMETHODCALLTYPE *GetTextBeforePosition)(SSD_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len);
    int     (STDMETHODCALLTYPE *GetParagraphReadingDirection)(SSD_SOURCE *self);  /* DWRITE_READING_DIRECTION */
    HRESULT (STDMETHODCALLTYPE *GetLocaleName)(SSD_SOURCE *self, UINT32 pos, UINT32 *len, const WCHAR **name);
    HRESULT (STDMETHODCALLTYPE *GetNumberSubstitution)(SSD_SOURCE *self, UINT32 pos, UINT32 *len, void **subst);
} SSD_SOURCE_VTBL;
struct SSD_SOURCE { const SSD_SOURCE_VTBL *lpVtbl; };

static HRESULT STDMETHODCALLTYPE ssd_src_qi(SSD_SOURCE *self, const GUID *riid, void **ppv) {
    if (ppv == NULL || riid == NULL) return E_POINTER;
    if (ssd_guid_eq(riid, &ssd_iid_iunknown) || ssd_guid_eq(riid, &ssd_iid_analysis_source)) {
        *ppv = self;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE ssd_src_addref(SSD_SOURCE *self) {
    (void)self; return 2;
}
static ULONG STDMETHODCALLTYPE ssd_src_release(SSD_SOURCE *self) {
    (void)self; return 1;                              /* static lifetime: never freed */
}
static HRESULT STDMETHODCALLTYPE ssd_src_text_at(SSD_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len) {
    (void)self;
    if (text == NULL || len == NULL) return E_POINTER;
    if (ssd_text != NULL && pos < ssd_text_len) { *text = ssd_text + pos; *len = ssd_text_len - pos; }
    else { *text = NULL; *len = 0; }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ssd_src_text_before(SSD_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len) {
    (void)self;
    if (text == NULL || len == NULL) return E_POINTER;
    if (ssd_text != NULL && pos > 0 && pos <= ssd_text_len) { *text = ssd_text; *len = pos; }
    else { *text = NULL; *len = 0; }
    return S_OK;
}
static int STDMETHODCALLTYPE ssd_src_para_dir(SSD_SOURCE *self) {
    (void)self;
    return 0;                                          /* DWRITE_READING_DIRECTION_LEFT_TO_RIGHT */
}
static HRESULT STDMETHODCALLTYPE ssd_src_locale(SSD_SOURCE *self, UINT32 pos, UINT32 *len, const WCHAR **name) {
    (void)self;
    if (name == NULL || len == NULL) return E_POINTER;
    *len = (pos < ssd_text_len) ? (ssd_text_len - pos) : 0;
    *name = ssd_locale;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ssd_src_numsub(SSD_SOURCE *self, UINT32 pos, UINT32 *len, void **subst) {
    (void)self;
    if (subst == NULL || len == NULL) return E_POINTER;
    *len = (pos < ssd_text_len) ? (ssd_text_len - pos) : 0;
    *subst = NULL;                                     /* no number substitution */
    return S_OK;
}

static const SSD_SOURCE_VTBL ssd_source_vtbl = {
    ssd_src_qi, ssd_src_addref, ssd_src_release,
    ssd_src_text_at, ssd_src_text_before, ssd_src_para_dir, ssd_src_locale, ssd_src_numsub
};
static SSD_SOURCE ssd_source = { &ssd_source_vtbl };

/* ================= SSD_SINK : IDWriteTextAnalysisSink ===================== */
/* Vtable order per SDK dwrite.h: IUnknown(3) + SetScriptAnalysis,
   SetLineBreakpoints, SetBidiLevel, SetNumberSubstitution. */

typedef struct SSD_SINK SSD_SINK;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_SINK *self, const GUID *riid, void **ppv);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_SINK *self);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_SINK *self);
    HRESULT (STDMETHODCALLTYPE *SetScriptAnalysis)(SSD_SINK *self, UINT32 pos, UINT32 len, const SSD_SCRIPT_ANALYSIS *sa);
    HRESULT (STDMETHODCALLTYPE *SetLineBreakpoints)(SSD_SINK *self, UINT32 pos, UINT32 len, const void *breakpoints);
    HRESULT (STDMETHODCALLTYPE *SetBidiLevel)(SSD_SINK *self, UINT32 pos, UINT32 len, UINT8 explicit_level, UINT8 resolved_level);
    HRESULT (STDMETHODCALLTYPE *SetNumberSubstitution)(SSD_SINK *self, UINT32 pos, UINT32 len, void *subst);
} SSD_SINK_VTBL;
struct SSD_SINK { const SSD_SINK_VTBL *lpVtbl; };

static HRESULT STDMETHODCALLTYPE ssd_sink_qi(SSD_SINK *self, const GUID *riid, void **ppv) {
    if (ppv == NULL || riid == NULL) return E_POINTER;
    if (ssd_guid_eq(riid, &ssd_iid_iunknown) || ssd_guid_eq(riid, &ssd_iid_analysis_sink)) {
        *ppv = self;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE ssd_sink_addref(SSD_SINK *self) {
    (void)self; return 2;
}
static ULONG STDMETHODCALLTYPE ssd_sink_release(SSD_SINK *self) {
    (void)self; return 1;
}
static HRESULT STDMETHODCALLTYPE ssd_sink_script(SSD_SINK *self, UINT32 pos, UINT32 len, const SSD_SCRIPT_ANALYSIS *sa) {
    (void)self;
    if (sa == NULL) return E_POINTER;
    if (!ssd_reserve_sruns(ssd_srun_n + 1)) { ssd_oom = 1; return E_OUTOFMEMORY; }
    ssd_sruns[ssd_srun_n].pos = pos;
    ssd_sruns[ssd_srun_n].len = len;
    ssd_sruns[ssd_srun_n].sa = *sa;
    ssd_srun_n++;
    return S_OK;
}
/* REAL, unlike the spike's stub: AnalyzeLineBreakpoints delivers one
   DWRITE_LINE_BREAKPOINT byte per UTF-16 unit of [pos, pos+len). */
static HRESULT STDMETHODCALLTYPE ssd_sink_breaks(SSD_SINK *self, UINT32 pos, UINT32 len, const void *breakpoints) {
    (void)self;
    if (breakpoints == NULL) return E_POINTER;
    if (len == 0) return S_OK;
    if (pos > ssd_text_len || len > ssd_text_len - pos) return E_INVALIDARG;
    if (!ssd_reserve_breaks(ssd_text_len)) { ssd_oom = 1; return E_OUTOFMEMORY; }
    memcpy(ssd_breaks + pos, breakpoints, (size_t)len);
    if (pos + len > ssd_break_n) ssd_break_n = pos + len;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ssd_sink_bidi(SSD_SINK *self, UINT32 pos, UINT32 len, UINT8 explicit_level, UINT8 resolved_level) {
    (void)self;
    if (!ssd_reserve_bruns(ssd_brun_n + 1)) { ssd_oom = 1; return E_OUTOFMEMORY; }
    ssd_bruns[ssd_brun_n].pos = pos;
    ssd_bruns[ssd_brun_n].len = len;
    ssd_bruns[ssd_brun_n].lexp = explicit_level;
    ssd_bruns[ssd_brun_n].lres = resolved_level;
    ssd_brun_n++;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE ssd_sink_numsub(SSD_SINK *self, UINT32 pos, UINT32 len, void *subst) {
    (void)self; (void)pos; (void)len; (void)subst;
    return S_OK;
}

static const SSD_SINK_VTBL ssd_sink_vtbl = {
    ssd_sink_qi, ssd_sink_addref, ssd_sink_release,
    ssd_sink_script, ssd_sink_breaks, ssd_sink_bidi, ssd_sink_numsub
};
static SSD_SINK ssd_sink = { &ssd_sink_vtbl };

/* ================= Called interfaces (consumer-side vtables) ============== */
/* Generic IUnknown view, used to Release anything. */
typedef struct SSD_UNK SSD_UNK;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_UNK*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_UNK*);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_UNK*);
} SSD_UNK_VTBL;
struct SSD_UNK { const SSD_UNK_VTBL *lpVtbl; };

/* IDWriteFactory: 3 IUnknown slots + 21 methods; only GetGdiInterop (slot 17)
   and CreateTextAnalyzer (slot 21) are typed, the rest are void* placeholders.
   Slot order transcribed verbatim from SDK dwrite.h. */
typedef struct SSD_FACTORY SSD_FACTORY;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_FACTORY*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_FACTORY*);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_FACTORY*);
    void *GetSystemFontCollection;        /* 3 */
    void *CreateCustomFontCollection;     /* 4 */
    void *RegisterFontCollectionLoader;   /* 5 */
    void *UnregisterFontCollectionLoader; /* 6 */
    void *CreateFontFileReference;        /* 7 */
    void *CreateCustomFontFileReference;  /* 8 */
    void *CreateFontFace;                 /* 9 */
    void *CreateRenderingParams;          /* 10 */
    void *CreateMonitorRenderingParams;   /* 11 */
    void *CreateCustomRenderingParams;    /* 12 */
    void *RegisterFontFileLoader;         /* 13 */
    void *UnregisterFontFileLoader;       /* 14 */
    void *CreateTextFormat;               /* 15 */
    void *CreateTypography;               /* 16 */
    HRESULT (STDMETHODCALLTYPE *GetGdiInterop)(SSD_FACTORY*, void **gdiInterop); /* 17 */
    void *CreateTextLayout;               /* 18 */
    void *CreateGdiCompatibleTextLayout;  /* 19 */
    void *CreateEllipsisTrimmingSign;     /* 20 */
    HRESULT (STDMETHODCALLTYPE *CreateTextAnalyzer)(SSD_FACTORY*, void **textAnalyzer); /* 21 */
    void *CreateNumberSubstitution;       /* 22 */
    void *CreateGlyphRunAnalysis;         /* 23 */
} SSD_FACTORY_VTBL;
struct SSD_FACTORY { const SSD_FACTORY_VTBL *lpVtbl; };

/* IDWriteGdiInterop: IUnknown + CreateFontFromLOGFONT, ConvertFontToLOGFONT,
   ConvertFontFaceToLOGFONT, CreateFontFaceFromHdc (slot 6), CreateBitmapRenderTarget. */
typedef struct SSD_INTEROP SSD_INTEROP;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_INTEROP*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_INTEROP*);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_INTEROP*);
    void *CreateFontFromLOGFONT;          /* 3 */
    void *ConvertFontToLOGFONT;           /* 4 */
    void *ConvertFontFaceToLOGFONT;       /* 5 */
    HRESULT (STDMETHODCALLTYPE *CreateFontFaceFromHdc)(SSD_INTEROP*, HDC hdc, void **fontFace); /* 6 */
    void *CreateBitmapRenderTarget;       /* 7 */
} SSD_INTEROP_VTBL;
struct SSD_INTEROP { const SSD_INTEROP_VTBL *lpVtbl; };

/* IDWriteTextAnalyzer: IUnknown + AnalyzeScript, AnalyzeBidi,
   AnalyzeNumberSubstitution, AnalyzeLineBreakpoints, GetGlyphs,
   GetGlyphPlacements, GetGdiCompatibleGlyphPlacements.
   features/numberSubstitution parameters are typed void* because simple_shaping
   always passes NULL (a pointer is a pointer, ABI-wise). */
typedef struct SSD_ANALYZER SSD_ANALYZER;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SSD_ANALYZER*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SSD_ANALYZER*);
    ULONG   (STDMETHODCALLTYPE *Release)(SSD_ANALYZER*);
    HRESULT (STDMETHODCALLTYPE *AnalyzeScript)(SSD_ANALYZER*, SSD_SOURCE *source, UINT32 pos, UINT32 len, SSD_SINK *sink); /* 3 */
    HRESULT (STDMETHODCALLTYPE *AnalyzeBidi)(SSD_ANALYZER*, SSD_SOURCE *source, UINT32 pos, UINT32 len, SSD_SINK *sink);   /* 4 */
    void *AnalyzeNumberSubstitution;      /* 5 */
    HRESULT (STDMETHODCALLTYPE *AnalyzeLineBreakpoints)(SSD_ANALYZER*, SSD_SOURCE *source, UINT32 pos, UINT32 len, SSD_SINK *sink); /* 6 */
    HRESULT (STDMETHODCALLTYPE *GetGlyphs)(SSD_ANALYZER*,                        /* 7 */
        const WCHAR *textString, UINT32 textLength, void *fontFace,
        BOOL isSideways, BOOL isRightToLeft,
        const SSD_SCRIPT_ANALYSIS *scriptAnalysis, const WCHAR *localeName,
        void *numberSubstitution, const void **features,
        const UINT32 *featureRangeLengths, UINT32 featureRanges,
        UINT32 maxGlyphCount,
        UINT16 *clusterMap, SSD_TEXT_PROPS *textProps,
        UINT16 *glyphIndices, SSD_GLYPH_PROPS *glyphProps,
        UINT32 *actualGlyphCount);
    HRESULT (STDMETHODCALLTYPE *GetGlyphPlacements)(SSD_ANALYZER*,               /* 8 */
        const WCHAR *textString, const UINT16 *clusterMap, SSD_TEXT_PROPS *textProps,
        UINT32 textLength, const UINT16 *glyphIndices,
        const SSD_GLYPH_PROPS *glyphProps, UINT32 glyphCount,
        void *fontFace, FLOAT fontEmSize,
        BOOL isSideways, BOOL isRightToLeft,
        const SSD_SCRIPT_ANALYSIS *scriptAnalysis, const WCHAR *localeName,
        const void **features, const UINT32 *featureRangeLengths, UINT32 featureRanges,
        FLOAT *glyphAdvances, SSD_GLYPH_OFFSET *glyphOffsets);
    void *GetGdiCompatibleGlyphPlacements; /* 9 */
} SSD_ANALYZER_VTBL;
struct SSD_ANALYZER { const SSD_ANALYZER_VTBL *lpVtbl; };

/* ================= Global COM handles ==================================== */

typedef HRESULT (WINAPI *SSD_PFN_DWRITECREATEFACTORY)(int factoryType, const GUID *iid, void **factory);

static HMODULE       ssd_dll = NULL;
static SSD_FACTORY  *ssd_factory = NULL;
static SSD_INTEROP  *ssd_interop = NULL;
static SSD_ANALYZER *ssd_analyzer = NULL;

/* ================= Flat C API for DWRITE_API ============================= */

/* ssd_open: LoadLibrary dwrite.dll, shared factory, GdiInterop, TextAnalyzer.
   1 on success; 0 with ssd_hr holding the failing HRESULT. Idempotent. */
static int ssd_open(void) {
    SSD_PFN_DWRITECREATEFACTORY create;
    HRESULT hr;
    void *raw = NULL;
    ssd_hr = SSD_HR_OK;
    if (ssd_analyzer) return 1;
    if (!ssd_dll) {
        ssd_dll = LoadLibraryW(L"dwrite.dll");
        if (!ssd_dll) { ssd_hr = SSD_HR_MOD_NOT_FOUND; return 0; }
    }
    create = (SSD_PFN_DWRITECREATEFACTORY)(void*)GetProcAddress(ssd_dll, "DWriteCreateFactory");
    if (!create) { ssd_hr = SSD_HR_PROC_NOT_FOUND; return 0; }
    if (!ssd_factory) {
        hr = create(0 /* DWRITE_FACTORY_TYPE_SHARED */, &ssd_iid_idwritefactory, &raw);
        if (hr < 0) { ssd_hr = (unsigned long)hr; return 0; }
        if (!raw) { ssd_hr = SSD_HR_FAIL; return 0; }
        ssd_factory = (SSD_FACTORY*)raw;
    }
    if (!ssd_interop) {
        raw = NULL;
        hr = ssd_factory->lpVtbl->GetGdiInterop(ssd_factory, &raw);
        if (hr < 0) { ssd_hr = (unsigned long)hr; return 0; }
        if (!raw) { ssd_hr = SSD_HR_FAIL; return 0; }
        ssd_interop = (SSD_INTEROP*)raw;
    }
    raw = NULL;
    hr = ssd_factory->lpVtbl->CreateTextAnalyzer(ssd_factory, &raw);
    if (hr < 0) { ssd_hr = (unsigned long)hr; return 0; }
    if (!raw) { ssd_hr = SSD_HR_FAIL; return 0; }
    ssd_analyzer = (SSD_ANALYZER*)raw;
    return 1;
}

/* ssd_close: release the COM objects, free the DLL, drop every buffer.
   Safe to call when never opened, and safe to call twice. */
static int ssd_close(void) {
    if (ssd_analyzer) {
        ((SSD_UNK*)ssd_analyzer)->lpVtbl->Release((SSD_UNK*)ssd_analyzer);
        ssd_analyzer = NULL;
    }
    if (ssd_interop) {
        ((SSD_UNK*)ssd_interop)->lpVtbl->Release((SSD_UNK*)ssd_interop);
        ssd_interop = NULL;
    }
    if (ssd_factory) {
        ((SSD_UNK*)ssd_factory)->lpVtbl->Release((SSD_UNK*)ssd_factory);
        ssd_factory = NULL;
    }
    if (ssd_dll) { FreeLibrary(ssd_dll); ssd_dll = NULL; }

    free(ssd_text);        ssd_text = NULL;        ssd_text_cap = 0;   ssd_text_len = 0;
    free(ssd_sruns);       ssd_sruns = NULL;       ssd_srun_cap = 0;   ssd_srun_n = 0;
    free(ssd_bruns);       ssd_bruns = NULL;       ssd_brun_cap = 0;   ssd_brun_n = 0;
    free(ssd_breaks);      ssd_breaks = NULL;      ssd_break_cap = 0;  ssd_break_n = 0;
    free(ssd_clusters);    ssd_clusters = NULL;
    free(ssd_text_props);  ssd_text_props = NULL;  ssd_run_cap = 0;
    free(ssd_glyphs);      ssd_glyphs = NULL;
    free(ssd_glyph_props); ssd_glyph_props = NULL;
    free(ssd_advances);    ssd_advances = NULL;
    free(ssd_offsets);     ssd_offsets = NULL;     ssd_glyph_cap = 0;
    ssd_glyph_n = 0;
    ssd_shaped_len = 0;
    ssd_oom = 0;
    return 1;
}

static unsigned long ssd_last_hr(void) { return ssd_hr; }

/* ssd_analyze: store the UTF-16 text, then AnalyzeScript + AnalyzeBidi over
   [0, len). Both run tables are reset first and reset again on ANY failure -
   a caller never sees a partly-filled table. A "success" that produced an
   empty run table is converted to E_FAIL here, which is what makes
   DWRITE_API.analyze's `runs_on_success' honest (ISSUE 11). */
static int ssd_analyze(const void *utf16, int len) {
    HRESULT hr;
    ssd_hr = SSD_HR_OK;
    ssd_oom = 0;
    ssd_srun_n = 0;
    ssd_brun_n = 0;
    if (!ssd_analyzer || !utf16 || len <= 0) { ssd_hr = SSD_HR_INVALIDARG; return 0; }
    if (!ssd_reserve_text((UINT32)len)) { ssd_hr = SSD_HR_OUTOFMEMORY; return 0; }
    memcpy(ssd_text, utf16, (size_t)len * sizeof(WCHAR));
    ssd_text_len = (UINT32)len;

    hr = ssd_analyzer->lpVtbl->AnalyzeScript(ssd_analyzer, &ssd_source, 0, (UINT32)len, &ssd_sink);
    if (hr < 0 || ssd_oom) {
        ssd_hr = ssd_oom ? SSD_HR_OUTOFMEMORY : (unsigned long)hr;
        ssd_srun_n = 0; ssd_brun_n = 0;
        return 0;
    }
    hr = ssd_analyzer->lpVtbl->AnalyzeBidi(ssd_analyzer, &ssd_source, 0, (UINT32)len, &ssd_sink);
    if (hr < 0 || ssd_oom) {
        ssd_hr = ssd_oom ? SSD_HR_OUTOFMEMORY : (unsigned long)hr;
        ssd_srun_n = 0; ssd_brun_n = 0;
        return 0;
    }
    if (ssd_srun_n < 1 || ssd_brun_n < 1) {
        ssd_hr = SSD_HR_FAIL;
        ssd_srun_n = 0; ssd_brun_n = 0;
        return 0;
    }
    return 1;
}

static int ssd_script_count(void) { return ssd_srun_n; }
static int ssd_script_pos(int i)  { return (i >= 0 && i < ssd_srun_n) ? (int)ssd_sruns[i].pos : -1; }
static int ssd_script_len(int i)  { return (i >= 0 && i < ssd_srun_n) ? (int)ssd_sruns[i].len : -1; }
static int ssd_script_id(int i)   { return (i >= 0 && i < ssd_srun_n) ? (int)ssd_sruns[i].sa.script : -1; }

/* Copy the run's DWRITE_SCRIPT_ANALYSIS bytes VERBATIM into caller memory;
   SCRIPT_ITEM carries them to the shaper unaltered. */
static int ssd_script_analysis(int i, void *out) {
    if (i < 0 || i >= ssd_srun_n || out == NULL) return 0;
    memcpy(out, &ssd_sruns[i].sa, sizeof(SSD_SCRIPT_ANALYSIS));
    return 1;
}
static int ssd_script_analysis_size(void) { return (int)sizeof(SSD_SCRIPT_ANALYSIS); }

static int ssd_bidi_count(void)   { return ssd_brun_n; }
static int ssd_bidi_pos(int i)    { return (i >= 0 && i < ssd_brun_n) ? (int)ssd_bruns[i].pos : -1; }
static int ssd_bidi_len(int i)    { return (i >= 0 && i < ssd_brun_n) ? (int)ssd_bruns[i].len : -1; }
static int ssd_bidi_level(int i)  { return (i >= 0 && i < ssd_brun_n) ? (int)ssd_bruns[i].lres : 0; }

/* ssd_analyze_breaks: AnalyzeLineBreakpoints over [0, len). The script and
   bidi run tables are LEFT ALONE (the itemizer intersects them with these
   breaks over the same string); only the breakpoint table is rebuilt. A
   success guarantees exactly one breakpoint byte per UTF-16 unit. */
static int ssd_analyze_breaks(const void *utf16, int len) {
    HRESULT hr;
    ssd_hr = SSD_HR_OK;
    ssd_oom = 0;
    ssd_break_n = 0;
    if (!ssd_analyzer || !utf16 || len <= 0) { ssd_hr = SSD_HR_INVALIDARG; return 0; }
    if (!ssd_reserve_text((UINT32)len) || !ssd_reserve_breaks((UINT32)len)) {
        ssd_hr = SSD_HR_OUTOFMEMORY;
        return 0;
    }
    memcpy(ssd_text, utf16, (size_t)len * sizeof(WCHAR));
    ssd_text_len = (UINT32)len;
    memset(ssd_breaks, 0, (size_t)len);
    hr = ssd_analyzer->lpVtbl->AnalyzeLineBreakpoints(ssd_analyzer, &ssd_source, 0, (UINT32)len, &ssd_sink);
    if (hr < 0 || ssd_oom) {
        ssd_hr = ssd_oom ? SSD_HR_OUTOFMEMORY : (unsigned long)hr;
        ssd_break_n = 0;
        return 0;
    }
    if (ssd_break_n != (UINT32)len) {
        ssd_hr = SSD_HR_FAIL;
        ssd_break_n = 0;
        return 0;
    }
    return 1;
}

static int ssd_break_count(void)   { return (int)ssd_break_n; }
static int ssd_break_before(int i) { return (i >= 0 && (UINT32)i < ssd_break_n) ? (int)(ssd_breaks[i] & 0x03u) : 0; }
static int ssd_break_after(int i)  { return (i >= 0 && (UINT32)i < ssd_break_n) ? (int)((ssd_breaks[i] >> 2) & 0x03u) : 0; }
static int ssd_break_is_ws(int i)  { return (i >= 0 && (UINT32)i < ssd_break_n) ? (int)((ssd_breaks[i] >> 4) & 0x01u) : 0; }
static int ssd_break_is_hyph(int i){ return (i >= 0 && (UINT32)i < ssd_break_n) ? (int)((ssd_breaks[i] >> 5) & 0x01u) : 0; }

/* ssd_create_face_from_hdc: IDWriteGdiInterop::CreateFontFaceFromHdc over the
   font currently selected into `hdc' - the D-S03 bridge from GDI realization
   to the shaper's IDWriteFontFace. NULL on failure with ssd_hr set. */
static void *ssd_create_face_from_hdc(void *hdc) {
    void *face = NULL;
    HRESULT hr;
    ssd_hr = SSD_HR_OK;
    if (!ssd_interop || !hdc) { ssd_hr = SSD_HR_INVALIDARG; return NULL; }
    hr = ssd_interop->lpVtbl->CreateFontFaceFromHdc(ssd_interop, (HDC)hdc, &face);
    if (hr < 0) { ssd_hr = (unsigned long)hr; return NULL; }
    if (!face) { ssd_hr = SSD_HR_FAIL; return NULL; }
    return face;
}

static void ssd_release_face(void *face) {
    if (face) ((SSD_UNK*)face)->lpVtbl->Release((SSD_UNK*)face);
}

/* ssd_shape_run: GetGlyphs + GetGlyphPlacements for ONE itemized run.
   `em' is the caller's pixel size verbatim (same-N, D-S03); `analysis' is the
   run's DWRITE_SCRIPT_ANALYSIS bytes, copied in verbatim (a NULL analysis
   means a zeroed one). Buffer discipline per A-C02: first allocation
   1.5n + 16 glyphs, grow-and-retry up to 3 attempts on
   ERROR_INSUFFICIENT_BUFFER. 1 on success (glyph table non-empty), 0 with
   ssd_hr set and the glyph table emptied otherwise. */
static int ssd_shape_run(const void *utf16, int len, void *face, double em, int rtl, const void *analysis) {
    SSD_SCRIPT_ANALYSIS sa;
    UINT32 actual = 0;
    UINT32 max_glyphs;
    HRESULT hr = S_OK;
    int attempt;

    ssd_hr = SSD_HR_OK;
    ssd_glyph_n = 0;
    ssd_shaped_len = 0;
    if (!ssd_analyzer || !utf16 || !face || len <= 0 || em <= 0.0) {
        ssd_hr = SSD_HR_INVALIDARG;
        return 0;
    }
    memset(&sa, 0, sizeof(sa));
    if (analysis) memcpy(&sa, analysis, sizeof(sa));
    if (!ssd_reserve_run_arrays((UINT32)len)) { ssd_hr = SSD_HR_OUTOFMEMORY; return 0; }

    max_glyphs = (UINT32)((3 * len) / 2 + 16);
    for (attempt = 0; attempt < 3; attempt++) {
        if (!ssd_reserve_glyph_arrays(max_glyphs)) { ssd_hr = SSD_HR_OUTOFMEMORY; return 0; }
        actual = 0;
        hr = ssd_analyzer->lpVtbl->GetGlyphs(ssd_analyzer,
            (const WCHAR*)utf16, (UINT32)len, face,
            FALSE, rtl ? TRUE : FALSE,
            &sa, ssd_locale,
            NULL /* numberSubstitution */, NULL /* features */, NULL, 0,
            max_glyphs,
            ssd_clusters, ssd_text_props, ssd_glyphs, ssd_glyph_props, &actual);
        if ((unsigned long)hr != SSD_HR_INSUFFICIENT_BUF) break;
        if (max_glyphs > 0x00100000u) break;
        max_glyphs *= 2u;
    }
    if (hr < 0) { ssd_hr = (unsigned long)hr; return 0; }
    if (actual < 1 || actual > ssd_glyph_cap) { ssd_hr = SSD_HR_FAIL; return 0; }

    hr = ssd_analyzer->lpVtbl->GetGlyphPlacements(ssd_analyzer,
        (const WCHAR*)utf16, ssd_clusters, ssd_text_props, (UINT32)len,
        ssd_glyphs, ssd_glyph_props, actual,
        face, (FLOAT)em,
        FALSE, rtl ? TRUE : FALSE,
        &sa, ssd_locale,
        NULL, NULL, 0,
        ssd_advances, ssd_offsets);
    if (hr < 0) { ssd_hr = (unsigned long)hr; return 0; }

    ssd_glyph_n = (int)actual;
    ssd_shaped_len = len;
    return 1;
}

static int          ssd_glyph_count(void)     { return ssd_glyph_n; }
static unsigned int ssd_glyph_id(int i)       { return (i >= 0 && i < ssd_glyph_n) ? (unsigned int)ssd_glyphs[i] : 0u; }
static double       ssd_glyph_advance(int i)  { return (i >= 0 && i < ssd_glyph_n) ? (double)ssd_advances[i] : 0.0; }
static double       ssd_glyph_dx(int i)       { return (i >= 0 && i < ssd_glyph_n) ? (double)ssd_offsets[i].advanceOffset : 0.0; }
static double       ssd_glyph_dy(int i)       { return (i >= 0 && i < ssd_glyph_n) ? (double)ssd_offsets[i].ascenderOffset : 0.0; }
static int          ssd_cluster_entry(int i)  { return (i >= 0 && i < ssd_shaped_len) ? (int)ssd_clusters[i] : -1; }

#endif /* SIMPLE_SHAPING_DWRITE_H */
