/*
 * dwrite_spike.h - FEASIBILITY SPIKE: drive IDWriteTextAnalyzer from Eiffel
 *                  through a plain-C COM shim (static vtables, no ATL, no C++).
 *
 * WHY PLAIN C AND HAND-DECLARED INTERFACES:
 *   The Windows SDK's dwrite.h (10.0.26100.0) is C++-only: every interface is
 *   declared as `interface DWRITE_DECLARE_INTERFACE("...") IFoo : public IUnknown`
 *   with no CINTERFACE/C-vtable branch (unlike d3d11.h). Eiffel inline-C bodies
 *   are compiled as C by finish_freezing, so including dwrite.h is not an option.
 *   Instead this header declares, in C, ONLY the slices of the DirectWrite ABI
 *   the spike touches: vtable structs whose slot ORDER is transcribed verbatim
 *   from the installed SDK header (method order = vtable order; unused slots are
 *   held by `void*` members so the layout stays exact). COM's binary contract
 *   (this-pointer + vtable of __stdcall function pointers) is what makes this
 *   legal; MSVC C and C++ share that ABI on x64.
 *
 * PATTERN (per simple_encryption.h / Eric Bezault):
 *   Implementations live in this .h, called from Eiffel `"C inline use"`
 *   externals. Everything is `static`; ALL externals must therefore live in ONE
 *   Eiffel class so they land in one generated translation unit and share state.
 *
 * LINKING:
 *   dwrite.dll is loaded with LoadLibraryW + GetProcAddress("DWriteCreateFactory")
 *   so no dwrite import library is needed (works on any toolchain config).
 *   gdi32 (CreateFontW/CreateCompatibleDC/SelectObject) comes in via
 *   `#pragma comment(lib, "gdi32.lib")`.
 *
 * SPIKE OBJECTS:
 *   - SPK_SOURCE implements IDWriteTextAnalysisSource {688e1a58-5094-47c8-adc8-fbcea60ae92b}
 *   - SPK_SINK   implements IDWriteTextAnalysisSink   {5810cd44-0ca0-4701-b3fa-bec5182ae4f6}
 *   Both are static-lifetime singletons: AddRef/Release keep no real count and
 *   never free (valid COM for objects the caller owns and outlives the calls).
 *   Every callback records an event (kind, thread id, position, length) so the
 *   Eiffel side can print call order and verify threading.
 *
 * Copyright (c) 2026 Larry Rix - MIT License (spike evidence, kept in-repo)
 */

#ifndef DWRITE_SPIKE_H
#define DWRITE_SPIKE_H

#include <windows.h>
#include <string.h>

#if defined(_MSC_VER)
#pragma comment(lib, "gdi32.lib")
#endif

/* ================= IIDs (hand-defined; no uuid.lib dependency) ============ */

static const GUID spk_iid_iunknown =
    {0x00000000, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID spk_iid_idwritefactory =            /* b859ee5a-d838-4b5b-a2e8-1adc7d93db48 */
    {0xb859ee5a, 0xd838, 0x4b5b, {0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48}};
static const GUID spk_iid_analysis_source =           /* 688e1a58-5094-47c8-adc8-fbcea60ae92b */
    {0x688e1a58, 0x5094, 0x47c8, {0xad, 0xc8, 0xfb, 0xce, 0xa6, 0x0a, 0xe9, 0x2b}};
static const GUID spk_iid_analysis_sink =             /* 5810cd44-0ca0-4701-b3fa-bec5182ae4f6 */
    {0x5810cd44, 0x0ca0, 0x4701, {0xb3, 0xfa, 0xbe, 0xc5, 0x18, 0x2a, 0xe4, 0xf6}};

static int spk_guid_eq(const GUID *a, const GUID *b) {
    return memcmp(a, b, sizeof(GUID)) == 0;
}

/* ================= DirectWrite POD types (ABI-exact) ====================== */

/* DWRITE_SCRIPT_ANALYSIS: UINT16 script; DWRITE_SCRIPT_SHAPES shapes (enum=int).
   MSVC lays this out as {u16, 2 pad, i32} in both C and C++. */
typedef struct {
    UINT16 script;
    int    shapes;
} SPK_SCRIPT_ANALYSIS;

/* DWRITE_SHAPING_TEXT_PROPERTIES / _GLYPH_PROPERTIES are UINT16 bitfield
   structs; the spike never reads the fields, so an opaque UINT16 with the same
   size/alignment stands in. DWRITE_LINE_BREAKPOINT likewise (UINT8). */
typedef struct { UINT16 bits; } SPK_TEXT_PROPS;
typedef struct { UINT16 bits; } SPK_GLYPH_PROPS;

typedef struct {
    FLOAT advanceOffset;
    FLOAT ascenderOffset;
} SPK_GLYPH_OFFSET;                                   /* DWRITE_GLYPH_OFFSET */

/* ================= Recorded state ========================================= */

#define SPK_MAX_TEXT   128
#define SPK_MAX_RUNS    64
#define SPK_MAX_EVENTS 512
#define SPK_MAX_GLYPHS 256

/* Event kinds (mirrored by the Eiffel side's event_kind_name):
   1 QI(source) 2 AddRef(source) 3 Release(source)
   4 GetTextAtPosition 5 GetTextBeforePosition 6 GetParagraphReadingDirection
   7 GetLocaleName 8 GetNumberSubstitution
   9 QI(sink) 10 AddRef(sink) 11 Release(sink)
   12 SetScriptAnalysis 13 SetLineBreakpoints 14 SetBidiLevel 15 SetNumberSubstitution
   100 marker: AnalyzeScript returned   101 marker: AnalyzeBidi returned */

static WCHAR         spk_text[SPK_MAX_TEXT];
static UINT32        spk_text_len = 0;
static unsigned long spk_hr = 0;                      /* last HRESULT seen */
static DWORD         spk_tid_main = 0;

static struct { UINT32 pos, len; UINT16 script; int shapes; } spk_sruns[SPK_MAX_RUNS];
static int spk_srun_count = 0;

static struct { UINT32 pos, len; UINT8 lexp, lres; } spk_bruns[SPK_MAX_RUNS];
static int spk_brun_count = 0;

static struct { int kind; DWORD tid; UINT32 pos, len; } spk_events[SPK_MAX_EVENTS];
static int spk_event_n = 0;                           /* stored (capped) */
static int spk_event_all = 0;                         /* total, even past cap */

static UINT16           spk_glyphs[SPK_MAX_GLYPHS];
static FLOAT            spk_advances[SPK_MAX_GLYPHS];
static SPK_GLYPH_OFFSET spk_offsets[SPK_MAX_GLYPHS];
static UINT16           spk_clusters[SPK_MAX_TEXT];
static int spk_glyph_n = 0;
static int spk_shaped_text_len = 0;

static void spk_event(int kind, UINT32 pos, UINT32 len) {
    spk_event_all++;
    if (spk_event_n < SPK_MAX_EVENTS) {
        spk_events[spk_event_n].kind = kind;
        spk_events[spk_event_n].tid = GetCurrentThreadId();
        spk_events[spk_event_n].pos = pos;
        spk_events[spk_event_n].len = len;
        spk_event_n++;
    }
}

/* ================= SPK_SOURCE : IDWriteTextAnalysisSource ================= */
/* Vtable order per SDK dwrite.h: IUnknown(3) + GetTextAtPosition,
   GetTextBeforePosition, GetParagraphReadingDirection, GetLocaleName,
   GetNumberSubstitution. NOTE the asymmetric parameter orders (string-then-
   length vs length-then-string) - transcribed exactly. */

typedef struct SPK_SOURCE SPK_SOURCE;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_SOURCE *self, const GUID *riid, void **ppv);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_SOURCE *self);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_SOURCE *self);
    HRESULT (STDMETHODCALLTYPE *GetTextAtPosition)(SPK_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len);
    HRESULT (STDMETHODCALLTYPE *GetTextBeforePosition)(SPK_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len);
    int     (STDMETHODCALLTYPE *GetParagraphReadingDirection)(SPK_SOURCE *self);  /* DWRITE_READING_DIRECTION */
    HRESULT (STDMETHODCALLTYPE *GetLocaleName)(SPK_SOURCE *self, UINT32 pos, UINT32 *len, const WCHAR **name);
    HRESULT (STDMETHODCALLTYPE *GetNumberSubstitution)(SPK_SOURCE *self, UINT32 pos, UINT32 *len, void **subst);
} SPK_SOURCE_VTBL;
struct SPK_SOURCE { const SPK_SOURCE_VTBL *lpVtbl; };

static HRESULT STDMETHODCALLTYPE spk_src_qi(SPK_SOURCE *self, const GUID *riid, void **ppv) {
    spk_event(1, 0, 0);
    if (ppv == NULL) return E_POINTER;
    if (spk_guid_eq(riid, &spk_iid_iunknown) || spk_guid_eq(riid, &spk_iid_analysis_source)) {
        *ppv = self;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE spk_src_addref(SPK_SOURCE *self) {
    (void)self; spk_event(2, 0, 0); return 2;
}
static ULONG STDMETHODCALLTYPE spk_src_release(SPK_SOURCE *self) {
    (void)self; spk_event(3, 0, 0); return 1;         /* static lifetime: never freed */
}
static HRESULT STDMETHODCALLTYPE spk_src_text_at(SPK_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len) {
    (void)self; spk_event(4, pos, 0);
    if (pos < spk_text_len) { *text = spk_text + pos; *len = spk_text_len - pos; }
    else { *text = NULL; *len = 0; }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE spk_src_text_before(SPK_SOURCE *self, UINT32 pos, const WCHAR **text, UINT32 *len) {
    (void)self; spk_event(5, pos, 0);
    if (pos > 0 && pos <= spk_text_len) { *text = spk_text; *len = pos; }
    else { *text = NULL; *len = 0; }
    return S_OK;
}
static int STDMETHODCALLTYPE spk_src_para_dir(SPK_SOURCE *self) {
    (void)self; spk_event(6, 0, 0);
    return 0;                                          /* DWRITE_READING_DIRECTION_LEFT_TO_RIGHT */
}
static HRESULT STDMETHODCALLTYPE spk_src_locale(SPK_SOURCE *self, UINT32 pos, UINT32 *len, const WCHAR **name) {
    static const WCHAR loc[] = L"en-us";
    (void)self; spk_event(7, pos, 0);
    *len = (pos < spk_text_len) ? (spk_text_len - pos) : 0;
    *name = loc;
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE spk_src_numsub(SPK_SOURCE *self, UINT32 pos, UINT32 *len, void **subst) {
    (void)self; spk_event(8, pos, 0);
    *len = (pos < spk_text_len) ? (spk_text_len - pos) : 0;
    *subst = NULL;                                     /* no number substitution */
    return S_OK;
}

static const SPK_SOURCE_VTBL spk_source_vtbl = {
    spk_src_qi, spk_src_addref, spk_src_release,
    spk_src_text_at, spk_src_text_before, spk_src_para_dir, spk_src_locale, spk_src_numsub
};
static SPK_SOURCE spk_source = { &spk_source_vtbl };

/* ================= SPK_SINK : IDWriteTextAnalysisSink ===================== */
/* Vtable order per SDK dwrite.h: IUnknown(3) + SetScriptAnalysis,
   SetLineBreakpoints, SetBidiLevel, SetNumberSubstitution. */

typedef struct SPK_SINK SPK_SINK;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_SINK *self, const GUID *riid, void **ppv);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_SINK *self);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_SINK *self);
    HRESULT (STDMETHODCALLTYPE *SetScriptAnalysis)(SPK_SINK *self, UINT32 pos, UINT32 len, const SPK_SCRIPT_ANALYSIS *sa);
    HRESULT (STDMETHODCALLTYPE *SetLineBreakpoints)(SPK_SINK *self, UINT32 pos, UINT32 len, const void *breakpoints);
    HRESULT (STDMETHODCALLTYPE *SetBidiLevel)(SPK_SINK *self, UINT32 pos, UINT32 len, UINT8 explicit_level, UINT8 resolved_level);
    HRESULT (STDMETHODCALLTYPE *SetNumberSubstitution)(SPK_SINK *self, UINT32 pos, UINT32 len, void *subst);
} SPK_SINK_VTBL;
struct SPK_SINK { const SPK_SINK_VTBL *lpVtbl; };

static HRESULT STDMETHODCALLTYPE spk_sink_qi(SPK_SINK *self, const GUID *riid, void **ppv) {
    spk_event(9, 0, 0);
    if (ppv == NULL) return E_POINTER;
    if (spk_guid_eq(riid, &spk_iid_iunknown) || spk_guid_eq(riid, &spk_iid_analysis_sink)) {
        *ppv = self;
        return S_OK;
    }
    *ppv = NULL;
    return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE spk_sink_addref(SPK_SINK *self) {
    (void)self; spk_event(10, 0, 0); return 2;
}
static ULONG STDMETHODCALLTYPE spk_sink_release(SPK_SINK *self) {
    (void)self; spk_event(11, 0, 0); return 1;
}
static HRESULT STDMETHODCALLTYPE spk_sink_script(SPK_SINK *self, UINT32 pos, UINT32 len, const SPK_SCRIPT_ANALYSIS *sa) {
    (void)self; spk_event(12, pos, len);
    if (spk_srun_count < SPK_MAX_RUNS) {
        spk_sruns[spk_srun_count].pos = pos;
        spk_sruns[spk_srun_count].len = len;
        spk_sruns[spk_srun_count].script = sa->script;
        spk_sruns[spk_srun_count].shapes = sa->shapes;
        spk_srun_count++;
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE spk_sink_breaks(SPK_SINK *self, UINT32 pos, UINT32 len, const void *breakpoints) {
    (void)self; (void)breakpoints; spk_event(13, pos, len);
    return S_OK;                                       /* not requested by this spike */
}
static HRESULT STDMETHODCALLTYPE spk_sink_bidi(SPK_SINK *self, UINT32 pos, UINT32 len, UINT8 explicit_level, UINT8 resolved_level) {
    (void)self; spk_event(14, pos, len);
    if (spk_brun_count < SPK_MAX_RUNS) {
        spk_bruns[spk_brun_count].pos = pos;
        spk_bruns[spk_brun_count].len = len;
        spk_bruns[spk_brun_count].lexp = explicit_level;
        spk_bruns[spk_brun_count].lres = resolved_level;
        spk_brun_count++;
    }
    return S_OK;
}
static HRESULT STDMETHODCALLTYPE spk_sink_numsub(SPK_SINK *self, UINT32 pos, UINT32 len, void *subst) {
    (void)self; (void)subst; spk_event(15, pos, len);
    return S_OK;
}

static const SPK_SINK_VTBL spk_sink_vtbl = {
    spk_sink_qi, spk_sink_addref, spk_sink_release,
    spk_sink_script, spk_sink_breaks, spk_sink_bidi, spk_sink_numsub
};
static SPK_SINK spk_sink = { &spk_sink_vtbl };

/* ================= Called interfaces (consumer-side vtables) ============== */
/* Generic IUnknown view, used to Release anything. */
typedef struct SPK_UNK SPK_UNK;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_UNK*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_UNK*);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_UNK*);
} SPK_UNK_VTBL;
struct SPK_UNK { const SPK_UNK_VTBL *lpVtbl; };
#define SPK_RELEASE(p) do { if (p) { ((SPK_UNK*)(p))->lpVtbl->Release((SPK_UNK*)(p)); (p) = NULL; } } while (0)

/* IDWriteFactory: 3 IUnknown slots + 21 methods; only GetGdiInterop (slot 17)
   and CreateTextAnalyzer (slot 21) are typed, the rest are void* placeholders.
   Slot order transcribed verbatim from SDK dwrite.h. */
typedef struct SPK_FACTORY SPK_FACTORY;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_FACTORY*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_FACTORY*);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_FACTORY*);
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
    HRESULT (STDMETHODCALLTYPE *GetGdiInterop)(SPK_FACTORY*, void **gdiInterop); /* 17 */
    void *CreateTextLayout;               /* 18 */
    void *CreateGdiCompatibleTextLayout;  /* 19 */
    void *CreateEllipsisTrimmingSign;     /* 20 */
    HRESULT (STDMETHODCALLTYPE *CreateTextAnalyzer)(SPK_FACTORY*, void **textAnalyzer); /* 21 */
    void *CreateNumberSubstitution;       /* 22 */
    void *CreateGlyphRunAnalysis;         /* 23 */
} SPK_FACTORY_VTBL;
struct SPK_FACTORY { const SPK_FACTORY_VTBL *lpVtbl; };

/* IDWriteGdiInterop: IUnknown + CreateFontFromLOGFONT, ConvertFontToLOGFONT,
   ConvertFontFaceToLOGFONT, CreateFontFaceFromHdc (slot 6), CreateBitmapRenderTarget. */
typedef struct SPK_INTEROP SPK_INTEROP;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_INTEROP*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_INTEROP*);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_INTEROP*);
    void *CreateFontFromLOGFONT;          /* 3 */
    void *ConvertFontToLOGFONT;           /* 4 */
    void *ConvertFontFaceToLOGFONT;       /* 5 */
    HRESULT (STDMETHODCALLTYPE *CreateFontFaceFromHdc)(SPK_INTEROP*, HDC hdc, void **fontFace); /* 6 */
    void *CreateBitmapRenderTarget;       /* 7 */
} SPK_INTEROP_VTBL;
struct SPK_INTEROP { const SPK_INTEROP_VTBL *lpVtbl; };

/* IDWriteTextAnalyzer: IUnknown + AnalyzeScript, AnalyzeBidi,
   AnalyzeNumberSubstitution, AnalyzeLineBreakpoints, GetGlyphs,
   GetGlyphPlacements, GetGdiCompatibleGlyphPlacements.
   features/numberSubstitution parameters are typed void* because the spike
   always passes NULL (a pointer is a pointer, ABI-wise). */
typedef struct SPK_ANALYZER SPK_ANALYZER;
typedef struct {
    HRESULT (STDMETHODCALLTYPE *QueryInterface)(SPK_ANALYZER*, const GUID*, void**);
    ULONG   (STDMETHODCALLTYPE *AddRef)(SPK_ANALYZER*);
    ULONG   (STDMETHODCALLTYPE *Release)(SPK_ANALYZER*);
    HRESULT (STDMETHODCALLTYPE *AnalyzeScript)(SPK_ANALYZER*, SPK_SOURCE *source, UINT32 pos, UINT32 len, SPK_SINK *sink); /* 3 */
    HRESULT (STDMETHODCALLTYPE *AnalyzeBidi)(SPK_ANALYZER*, SPK_SOURCE *source, UINT32 pos, UINT32 len, SPK_SINK *sink);   /* 4 */
    void *AnalyzeNumberSubstitution;      /* 5 */
    void *AnalyzeLineBreakpoints;         /* 6 */
    HRESULT (STDMETHODCALLTYPE *GetGlyphs)(SPK_ANALYZER*,                        /* 7 */
        const WCHAR *textString, UINT32 textLength, void *fontFace,
        BOOL isSideways, BOOL isRightToLeft,
        const SPK_SCRIPT_ANALYSIS *scriptAnalysis, const WCHAR *localeName,
        void *numberSubstitution, const void **features,
        const UINT32 *featureRangeLengths, UINT32 featureRanges,
        UINT32 maxGlyphCount,
        UINT16 *clusterMap, SPK_TEXT_PROPS *textProps,
        UINT16 *glyphIndices, SPK_GLYPH_PROPS *glyphProps,
        UINT32 *actualGlyphCount);
    HRESULT (STDMETHODCALLTYPE *GetGlyphPlacements)(SPK_ANALYZER*,               /* 8 */
        const WCHAR *textString, const UINT16 *clusterMap, SPK_TEXT_PROPS *textProps,
        UINT32 textLength, const UINT16 *glyphIndices,
        const SPK_GLYPH_PROPS *glyphProps, UINT32 glyphCount,
        void *fontFace, FLOAT fontEmSize,
        BOOL isSideways, BOOL isRightToLeft,
        const SPK_SCRIPT_ANALYSIS *scriptAnalysis, const WCHAR *localeName,
        const void **features, const UINT32 *featureRangeLengths, UINT32 featureRanges,
        FLOAT *glyphAdvances, SPK_GLYPH_OFFSET *glyphOffsets);
    void *GetGdiCompatibleGlyphPlacements; /* 9 */
} SPK_ANALYZER_VTBL;
struct SPK_ANALYZER { const SPK_ANALYZER_VTBL *lpVtbl; };

/* ================= Global COM handles ==================================== */

typedef HRESULT (WINAPI *SPK_PFN_DWRITECREATEFACTORY)(int factoryType, const GUID *iid, void **factory);

static HMODULE       spk_dll = NULL;
static SPK_FACTORY  *spk_factory = NULL;
static SPK_INTEROP  *spk_interop = NULL;
static SPK_ANALYZER *spk_analyzer = NULL;

/* ================= Flat C API for Eiffel ================================= */

/* dw_open: LoadLibrary dwrite.dll, create shared factory, gdi interop, analyzer.
   Returns 1 on success; 0 with spk_hr holding the failing HRESULT (or 1 for
   load/getproc failure, distinguishable via GetLastError not kept - spike). */
static int spk_open(void) {
    SPK_PFN_DWRITECREATEFACTORY create;
    HRESULT hr;
    void *raw = NULL;
    spk_hr = 0;
    if (spk_analyzer) return 1;
    spk_dll = LoadLibraryW(L"dwrite.dll");
    if (!spk_dll) { spk_hr = 0x8007007E; return 0; }   /* HRESULT_FROM_WIN32(ERROR_MOD_NOT_FOUND) */
    create = (SPK_PFN_DWRITECREATEFACTORY)(void*)GetProcAddress(spk_dll, "DWriteCreateFactory");
    if (!create) { spk_hr = 0x8007007F; return 0; }    /* ERROR_PROC_NOT_FOUND */
    hr = create(0 /* DWRITE_FACTORY_TYPE_SHARED */, &spk_iid_idwritefactory, &raw);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }
    spk_factory = (SPK_FACTORY*)raw;
    raw = NULL;
    hr = spk_factory->lpVtbl->GetGdiInterop(spk_factory, &raw);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }
    spk_interop = (SPK_INTEROP*)raw;
    raw = NULL;
    hr = spk_factory->lpVtbl->CreateTextAnalyzer(spk_factory, &raw);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }
    spk_analyzer = (SPK_ANALYZER*)raw;
    return 1;
}

static unsigned long spk_last_hr(void) { return spk_hr; }
static int spk_main_tid(void) { return (int)GetCurrentThreadId(); }

/* dw_analyze: copy UTF-16 text, run AnalyzeScript + AnalyzeBidi over [0,len).
   Marker events 100/101 separate the two phases in the event log. */
static int spk_analyze(const void *utf16, int len) {
    HRESULT hr;
    if (!spk_analyzer || len <= 0 || len > SPK_MAX_TEXT) { spk_hr = 0x80070057; return 0; } /* E_INVALIDARG */
    memcpy(spk_text, utf16, (size_t)len * sizeof(WCHAR));
    spk_text_len = (UINT32)len;
    spk_srun_count = 0; spk_brun_count = 0; spk_event_n = 0; spk_event_all = 0;
    spk_tid_main = GetCurrentThreadId();
    hr = spk_analyzer->lpVtbl->AnalyzeScript(spk_analyzer, &spk_source, 0, (UINT32)len, &spk_sink);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }
    spk_event(100, 0, 0);
    hr = spk_analyzer->lpVtbl->AnalyzeBidi(spk_analyzer, &spk_source, 0, (UINT32)len, &spk_sink);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }
    spk_event(101, 0, 0);
    return 1;
}

static int spk_script_count(void) { return spk_srun_count; }
static int spk_script_pos(int i)  { return (i >= 0 && i < spk_srun_count) ? (int)spk_sruns[i].pos : -1; }
static int spk_script_len(int i)  { return (i >= 0 && i < spk_srun_count) ? (int)spk_sruns[i].len : -1; }
static int spk_script_id(int i)   { return (i >= 0 && i < spk_srun_count) ? (int)spk_sruns[i].script : -1; }
static int spk_script_shapes(int i) { return (i >= 0 && i < spk_srun_count) ? spk_sruns[i].shapes : -1; }

static int spk_bidi_count(void)   { return spk_brun_count; }
static int spk_bidi_pos(int i)    { return (i >= 0 && i < spk_brun_count) ? (int)spk_bruns[i].pos : -1; }
static int spk_bidi_len(int i)    { return (i >= 0 && i < spk_brun_count) ? (int)spk_bruns[i].len : -1; }
static int spk_bidi_explicit(int i) { return (i >= 0 && i < spk_brun_count) ? (int)spk_bruns[i].lexp : -1; }
static int spk_bidi_resolved(int i) { return (i >= 0 && i < spk_brun_count) ? (int)spk_bruns[i].lres : -1; }

static int spk_event_total(void)  { return spk_event_all; }
static int spk_event_stored(void) { return spk_event_n; }
static int spk_event_kind(int i)  { return (i >= 0 && i < spk_event_n) ? spk_events[i].kind : -1; }
static int spk_event_tid(int i)   { return (i >= 0 && i < spk_event_n) ? (int)spk_events[i].tid : -1; }
static int spk_event_pos(int i)   { return (i >= 0 && i < spk_event_n) ? (int)spk_events[i].pos : -1; }
static int spk_event_len(int i)   { return (i >= 0 && i < spk_event_n) ? (int)spk_events[i].len : -1; }

/* dw_shape_run: IDWriteGdiInterop::CreateFontFaceFromHdc over a Segoe UI HFONT
   (the research's chosen GDI bridge), then GetGlyphs + GetGlyphPlacements at
   px em size. The HFONT height only picks the font file; DirectWrite sizes by
   the fontEmSize argument (DIPs; 16 DIP = 16 px at 96 DPI).
   text_pos/text_len select the run inside the analyzed string; script_id and
   shapes must be the values AnalyzeScript reported for that run.
   Returns the glyph count (> 0) or 0 on failure (spk_hr set). */
static int spk_shape(const void *utf16, int text_pos, int text_len,
                     int script_id, int shapes, int rtl, double px) {
    HFONT font, old_font;
    HDC dc;
    void *face = NULL;
    SPK_SCRIPT_ANALYSIS sa;
    SPK_TEXT_PROPS text_props[SPK_MAX_TEXT];
    SPK_GLYPH_PROPS glyph_props[SPK_MAX_GLYPHS];
    UINT32 actual = 0;
    UINT32 max_glyphs;
    HRESULT hr;
    const WCHAR *run_text = (const WCHAR*)utf16 + text_pos;

    spk_glyph_n = 0;
    spk_shaped_text_len = 0;
    if (!spk_interop || !spk_analyzer || text_len <= 0 || text_len > SPK_MAX_TEXT) {
        spk_hr = 0x80070057; return 0;
    }
    font = CreateFontW(-(int)px, 0, 0, 0, FW_NORMAL, 0, 0, 0,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
    if (!font) { spk_hr = 0x8007000E; return 0; }
    dc = CreateCompatibleDC(NULL);
    if (!dc) { DeleteObject(font); spk_hr = 0x8007000E; return 0; }
    old_font = (HFONT)SelectObject(dc, font);
    hr = spk_interop->lpVtbl->CreateFontFaceFromHdc(spk_interop, dc, &face);
    SelectObject(dc, old_font);
    DeleteDC(dc);
    DeleteObject(font);                                /* face holds the font data now */
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }

    sa.script = (UINT16)script_id;
    sa.shapes = shapes;
    max_glyphs = (UINT32)(3 * text_len / 2 + 16);
    if (max_glyphs > SPK_MAX_GLYPHS) max_glyphs = SPK_MAX_GLYPHS;

    hr = spk_analyzer->lpVtbl->GetGlyphs(spk_analyzer,
        run_text, (UINT32)text_len, face,
        FALSE, rtl ? TRUE : FALSE,
        &sa, L"en-us",
        NULL /* numberSubstitution */, NULL /* features */, NULL, 0,
        max_glyphs,
        spk_clusters, text_props, spk_glyphs, glyph_props, &actual);
    if (hr < 0) { spk_hr = (unsigned long)hr; SPK_RELEASE(face); return 0; }

    hr = spk_analyzer->lpVtbl->GetGlyphPlacements(spk_analyzer,
        run_text, spk_clusters, text_props, (UINT32)text_len,
        spk_glyphs, glyph_props, actual,
        face, (FLOAT)px,
        FALSE, rtl ? TRUE : FALSE,
        &sa, L"en-us",
        NULL, NULL, 0,
        spk_advances, spk_offsets);
    SPK_RELEASE(face);
    if (hr < 0) { spk_hr = (unsigned long)hr; return 0; }

    spk_glyph_n = (int)actual;
    spk_shaped_text_len = text_len;
    return spk_glyph_n;
}

static int    spk_glyph_id(int i)      { return (i >= 0 && i < spk_glyph_n) ? (int)spk_glyphs[i] : -1; }
static double spk_glyph_advance(int i) { return (i >= 0 && i < spk_glyph_n) ? (double)spk_advances[i] : 0.0; }
static double spk_glyph_dx(int i)      { return (i >= 0 && i < spk_glyph_n) ? (double)spk_offsets[i].advanceOffset : 0.0; }
static double spk_glyph_dy(int i)      { return (i >= 0 && i < spk_glyph_n) ? (double)spk_offsets[i].ascenderOffset : 0.0; }
static int    spk_cluster_entry(int i) { return (i >= 0 && i < spk_shaped_text_len) ? (int)spk_clusters[i] : -1; }

static int spk_close(void) {
    SPK_RELEASE(spk_analyzer);
    SPK_RELEASE(spk_interop);
    SPK_RELEASE(spk_factory);
    if (spk_dll) { FreeLibrary(spk_dll); spk_dll = NULL; }
    return 1;
}

#endif /* DWRITE_SPIKE_H */
