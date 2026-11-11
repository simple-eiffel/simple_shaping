/* simple_shaping_ft_win.h - shaped text on Windows drawn through cairo's FreeType
   backend (simple_shaping#8, 2026-11-11).

   Why: Larry's same-everywhere rule. Gray antialiasing through cairo's win32 font
   backend (GDI grayscale) thins small marks below the gw03 gate, while Linux's
   FreeType gray passes it; drawing Windows' shaped runs with FreeType too lets
   them be gray like every other platform.

   How: the IDWriteFontFace the shaper already made for a font (SHAPING_FONT's
   `backend_face') names the font file; DirectWrite's own font file stream reads
   it (any loader: system fonts, GDI private fonts, any path), and one
   ReadFileFragment over the whole file gives a pointer into the file DirectWrite
   mapped. FreeType opens that memory (FT_New_Memory_Face) at the face's index,
   cairo builds a face over it (cairo_ft_font_face_create_for_ft_face), and a
   user-data hook on that cairo face releases FreeType, the fragment and the
   stream when cairo lets the face go. DirectWrite's glyph ids are the file's
   own glyph indices, so the shaper's ids and FreeType's are one id space.

   FreeType's entry points come from the freetype.dll cairo.dll already loaded
   (simple_cairo's runtime set), so no import library is needed; cairo-ft.h is
   not used because it needs FreeType's headers, so the two cairo entry points
   are declared here with opaque pointers. No static state: everything a face
   needs rides on its own holder. */

#ifndef SIMPLE_SHAPING_FT_WIN_H
#define SIMPLE_SHAPING_FT_WIN_H

#ifdef _WIN32

#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <cairo.h>

cairo_public cairo_font_face_t* cairo_ft_font_face_create_for_ft_face(void* face, int load_flags);
cairo_public void cairo_ft_font_face_set_synthesize(cairo_font_face_t* font_face, unsigned int synth_flags);

/* COM by slot: the n-th method of `obj''s vtable. */
#define SSF_SLOT(obj, n) (((void**) (*(void***) (obj)))[n])

typedef ULONG (STDMETHODCALLTYPE *SSF_RELEASE)(void* self);                                      /* IUnknown 2 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_GET_FILES)(void* self, UINT32* count, void** files);      /* IDWriteFontFace 4 */
typedef UINT32 (STDMETHODCALLTYPE *SSF_GET_INDEX)(void* self);                                   /* IDWriteFontFace 5 */
typedef int (STDMETHODCALLTYPE *SSF_GET_SIMULATIONS)(void* self);                                /* IDWriteFontFace 6 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_GET_KEY)(void* self, const void** key, UINT32* size);     /* IDWriteFontFile 3 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_GET_LOADER)(void* self, void** loader);                   /* IDWriteFontFile 4 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_CREATE_STREAM)(void* self, const void* key, UINT32 size, void** stream); /* IDWriteFontFileLoader 3 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_READ_FRAGMENT)(void* self, const void** start, UINT64 offset, UINT64 size, void** context); /* IDWriteFontFileStream 3 */
typedef void (STDMETHODCALLTYPE *SSF_RELEASE_FRAGMENT)(void* self, void* context);                /* IDWriteFontFileStream 4 */
typedef HRESULT (STDMETHODCALLTYPE *SSF_GET_FILE_SIZE)(void* self, UINT64* size);                 /* IDWriteFontFileStream 5 */

typedef int (*SSF_FT_INIT)(void** library);
typedef int (*SSF_FT_NEW_MEMORY_FACE)(void* library, const unsigned char* base, long size, long index, void** face);
typedef int (*SSF_FT_DONE_FACE)(void* face);
typedef int (*SSF_FT_DONE_LIBRARY)(void* library);

/* What a FreeType-backed cairo face keeps alive until cairo lets it go. */
typedef struct {
    void* library;
    void* face;
    void* stream;
    void* fragment;
    SSF_FT_DONE_FACE done_face;
    SSF_FT_DONE_LIBRARY done_library;
} SSF_HOLDER;

static const cairo_user_data_key_t ssf_holder_key = { 0 };

static void ssf_release_holder(void* a_holder)
{
    SSF_HOLDER* h = (SSF_HOLDER*) a_holder;
    if (!h) return;
    if (h->face && h->done_face) h->done_face(h->face);
    if (h->library && h->done_library) h->done_library(h->library);
    if (h->stream) {
        if (h->fragment) ((SSF_RELEASE_FRAGMENT) SSF_SLOT(h->stream, 4))(h->stream, h->fragment);
        ((SSF_RELEASE) SSF_SLOT(h->stream, 2))(h->stream);
    }
    free(h);
}

static void ssf_message(char* a_out, int a_cap, const char* a_text)
{
    if (a_out && a_cap > 0) {
        strncpy(a_out, a_text, (size_t) (a_cap - 1));
        a_out[a_cap - 1] = 0;
    }
}

/* A cairo face drawing `a_dwrite_face''s font through FreeType, with one reference
   for the caller; null (and the reason in `a_message') when it cannot be made, so
   the caller can fall back to the win32 face. */
static cairo_font_face_t* ssf_face_for_dwrite_face(void* a_dwrite_face, char* a_message, int a_cap)
{
    HMODULE l_ft = GetModuleHandleW(L"freetype.dll");
    SSF_FT_INIT l_init;
    SSF_FT_NEW_MEMORY_FACE l_new_face;
    UINT32 l_count = 0, l_key_size = 0, l_index;
    void* l_files[4] = { 0, 0, 0, 0 };
    void* l_loader = NULL;
    const void* l_key = NULL;
    const void* l_base = NULL;
    UINT64 l_size = 0;
    int l_simulations, i;
    SSF_HOLDER* h;
    cairo_font_face_t* l_cairo = NULL;

    ssf_message(a_message, a_cap, "");
    if (!a_dwrite_face) { ssf_message(a_message, a_cap, "no DirectWrite face"); return NULL; }
    if (!l_ft) { ssf_message(a_message, a_cap, "freetype.dll is not loaded"); return NULL; }
    l_init = (SSF_FT_INIT) (void*) GetProcAddress(l_ft, "FT_Init_FreeType");
    l_new_face = (SSF_FT_NEW_MEMORY_FACE) (void*) GetProcAddress(l_ft, "FT_New_Memory_Face");
    h = (SSF_HOLDER*) calloc(1, sizeof(SSF_HOLDER));
    if (!h) { ssf_message(a_message, a_cap, "out of memory"); return NULL; }
    h->done_face = (SSF_FT_DONE_FACE) (void*) GetProcAddress(l_ft, "FT_Done_Face");
    h->done_library = (SSF_FT_DONE_LIBRARY) (void*) GetProcAddress(l_ft, "FT_Done_FreeType");
    if (!l_init || !l_new_face || !h->done_face || !h->done_library) {
        free(h); ssf_message(a_message, a_cap, "freetype.dll lacks an entry point"); return NULL;
    }
    /* the face's file (a face of more than one file is not drawn this way) */
    if (FAILED(((SSF_GET_FILES) SSF_SLOT(a_dwrite_face, 4))(a_dwrite_face, &l_count, NULL)) || l_count != 1
        || FAILED(((SSF_GET_FILES) SSF_SLOT(a_dwrite_face, 4))(a_dwrite_face, &l_count, l_files)) || !l_files[0]) {
        free(h); ssf_message(a_message, a_cap, "the face is not one font file"); return NULL;
    }
    l_index = ((SSF_GET_INDEX) SSF_SLOT(a_dwrite_face, 5))(a_dwrite_face);
    l_simulations = ((SSF_GET_SIMULATIONS) SSF_SLOT(a_dwrite_face, 6))(a_dwrite_face);
    if (SUCCEEDED(((SSF_GET_KEY) SSF_SLOT(l_files[0], 3))(l_files[0], &l_key, &l_key_size))
        && SUCCEEDED(((SSF_GET_LOADER) SSF_SLOT(l_files[0], 4))(l_files[0], &l_loader)) && l_loader) {
        if (FAILED(((SSF_CREATE_STREAM) SSF_SLOT(l_loader, 3))(l_loader, l_key, l_key_size, &h->stream))) h->stream = NULL;
        ((SSF_RELEASE) SSF_SLOT(l_loader, 2))(l_loader);
    }
    for (i = 0; i < 4; i++) if (l_files[i]) ((SSF_RELEASE) SSF_SLOT(l_files[i], 2))(l_files[i]);
    if (!h->stream) { ssf_release_holder(h); ssf_message(a_message, a_cap, "the font file could not be opened"); return NULL; }
    if (FAILED(((SSF_GET_FILE_SIZE) SSF_SLOT(h->stream, 5))(h->stream, &l_size)) || l_size == 0 || l_size > 0x7FFFFFFF
        || FAILED(((SSF_READ_FRAGMENT) SSF_SLOT(h->stream, 3))(h->stream, &l_base, 0, l_size, &h->fragment)) || !l_base) {
        h->fragment = NULL;
        ssf_release_holder(h); ssf_message(a_message, a_cap, "the font file could not be read"); return NULL;
    }
    if (l_init(&h->library) != 0) {
        h->library = NULL;
        ssf_release_holder(h); ssf_message(a_message, a_cap, "FreeType could not start"); return NULL;
    }
    if (l_new_face(h->library, (const unsigned char*) l_base, (long) l_size, (long) l_index, &h->face) != 0) {
        h->face = NULL;
        ssf_release_holder(h); ssf_message(a_message, a_cap, "FreeType could not open the font"); return NULL;
    }
    l_cairo = cairo_ft_font_face_create_for_ft_face(h->face, 0);
    if (!l_cairo || cairo_font_face_status(l_cairo) != CAIRO_STATUS_SUCCESS
        || cairo_font_face_set_user_data(l_cairo, &ssf_holder_key, h, ssf_release_holder) != CAIRO_STATUS_SUCCESS) {
        if (l_cairo) cairo_font_face_destroy(l_cairo);
        ssf_release_holder(h); ssf_message(a_message, a_cap, "cairo could not use the FreeType face"); return NULL;
    }
    /* DWRITE_FONT_SIMULATIONS: 1 bold, 2 oblique; cairo's FreeType synthesis: 1 bold, 2 oblique */
    if (l_simulations & 3) cairo_ft_font_face_set_synthesize(l_cairo, (unsigned int) (l_simulations & 3));
    return l_cairo;
}

#endif /* _WIN32 */

#endif /* SIMPLE_SHAPING_FT_WIN_H */
