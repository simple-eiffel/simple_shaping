/*
 * sephone_text.c - see sephone_text.h. Built into apps that name it under
 * [native] sources, with the libraries from runtime/native/build_text.sh.
 */
#include <cairo.h>
#include <cairo-ft.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_MULTIPLE_MASTERS_H
#include <fribidi.h>
#include <hb.h>
#include <hb-ot.h>
#include <stdlib.h>
#include <fontconfig/fontconfig.h>
#include <string.h>
#include <strings.h>
#include "simple_shaping_posix.h"

#define WEIGHT_AXIS FT_MAKE_TAG('w', 'g', 'h', 't')

typedef struct {
	hb_blob_t *blob;
	hb_face_t *face;
	hb_font_t *font;
	FT_Face ft;
	cairo_font_face_t *cairo;
	int size;
} st_font;

static FT_Library s_ft = NULL;
static hb_buffer_t *s_buffer = NULL;
static cairo_user_data_key_t s_ft_key;

/* ------------------------------------------------------------------- bidi */

int st_bidi(const uint32_t *text, int count, int direction, uint8_t *levels)
{
	FriBidiCharType *types;
	FriBidiBracketType *brackets;
	FriBidiParType base = direction == 0 ? FRIBIDI_PAR_LTR : direction == 1 ? FRIBIDI_PAR_RTL : FRIBIDI_PAR_ON;
	if (count <= 0) return direction == 1 ? 1 : 0;
	types = (FriBidiCharType *)malloc(sizeof(FriBidiCharType) * (size_t)count);
	brackets = (FriBidiBracketType *)malloc(sizeof(FriBidiBracketType) * (size_t)count);
	if (!types || !brackets) {
		free(types);
		free(brackets);
		return 0;
	}
	fribidi_get_bidi_types((const FriBidiChar *)text, count, types);
	fribidi_get_bracket_types((const FriBidiChar *)text, count, types, brackets);
	fribidi_get_par_embedding_levels_ex(types, brackets, count, &base, (FriBidiLevel *)levels);
	free(types);
	free(brackets);
	return FRIBIDI_DIR_TO_LEVEL(base) & 1;
}

/* ----------------------------------------------------------------- script */

int st_script(uint32_t code) { return (int)hb_unicode_script(hb_unicode_funcs_get_default(), code); }
int st_script_common(void) { return (int)HB_SCRIPT_COMMON; }
int st_script_inherited(void) { return (int)HB_SCRIPT_INHERITED; }
int st_script_latin(void) { return (int)HB_SCRIPT_LATIN; }

/* ------------------------------------------------------------------ fonts */

/* A variable font, such as Android's Roboto, needs telling which weight is wanted. */
static void set_weight(st_font *f, int weight)
{
	FT_MM_Var *axes = NULL;
	if (FT_Get_MM_Var(f->ft, &axes) == 0 && axes) {
		FT_Fixed coords[16];
		FT_UInt i, n = axes->num_axis < 16 ? axes->num_axis : 16;
		int has_weight = 0;
		for (i = 0; i < n; i++) {
			coords[i] = axes->axis[i].def;
			if (axes->axis[i].tag == WEIGHT_AXIS) {
				coords[i] = (FT_Fixed)weight << 16;
				has_weight = 1;
			}
		}
		if (has_weight) {
			hb_variation_t variation;
			variation.tag = HB_TAG('w', 'g', 'h', 't');
			variation.value = (float)weight;
			FT_Set_Var_Design_Coordinates(f->ft, n, coords);
			hb_font_set_variations(f->font, &variation, 1);
		}
		FT_Done_MM_Var(s_ft, axes);
	}
}

int st_file_covers(const char *path, uint32_t code)
{
	FT_Face face;
	int result;
	if (!s_ft && FT_Init_FreeType(&s_ft) != 0) return 0;
	if (FT_New_Face(s_ft, path, 0, &face) != 0) return 0;
	result = FT_Get_Char_Index(face, code) != 0;
	FT_Done_Face(face);
	return result;
}

void *st_font_open(const char *path, int index, int weight, int italic)
{
	st_font *f;
	(void)italic;   /* fontconfig already chose the italic face */
	if (!s_ft && FT_Init_FreeType(&s_ft) != 0) return NULL;
	f = (st_font *)calloc(1, sizeof(st_font));
	if (!f) return NULL;
	if (FT_New_Face(s_ft, path, index, &f->ft) != 0) {
		free(f);
		return NULL;
	}
	f->blob = hb_blob_create_from_file(path);
	f->face = hb_face_create(f->blob, (unsigned int)index);
	f->font = hb_font_create(f->face);
	set_weight(f, weight);
	f->cairo = cairo_ft_font_face_create_for_ft_face(f->ft, 0);
	/* cairo keeps the FreeType face in use: it goes when cairo lets go. */
	cairo_font_face_set_user_data(f->cairo, &s_ft_key, f->ft, (cairo_destroy_func_t)FT_Done_Face);
	return f;
}

void st_font_close(void *font)
{
	st_font *f = (st_font *)font;
	if (!f) return;
	cairo_font_face_destroy(f->cairo);
	hb_font_destroy(f->font);
	hb_face_destroy(f->face);
	hb_blob_destroy(f->blob);
	free(f);
}

static void set_size(st_font *f, int pixel_size)
{
	if (f->size != pixel_size) {
		hb_font_set_scale(f->font, pixel_size * 64, pixel_size * 64);
		f->size = pixel_size;
	}
}

double st_font_ascent(void *font, int pixel_size)
{
	st_font *f = (st_font *)font;
	hb_font_extents_t e;
	set_size(f, pixel_size);
	if (!hb_font_get_h_extents(f->font, &e)) return (double)pixel_size;
	return (double)e.ascender / 64.0;
}

double st_font_descent(void *font, int pixel_size)
{
	st_font *f = (st_font *)font;
	hb_font_extents_t e;
	set_size(f, pixel_size);
	if (!hb_font_get_h_extents(f->font, &e)) return 0.0;
	return (double)(-e.descender) / 64.0;
}

void *st_font_cairo_face(void *font)
{
	return ((st_font *)font)->cairo;
}

/* ---------------------------------------------------------------- shaping */

int st_shape(void *font, int pixel_size, const uint32_t *text, int text_count,
	int start, int count, int rtl, int script)
{
	st_font *f = (st_font *)font;
	if (!f || count <= 0) return -1;
	if (!s_buffer) s_buffer = hb_buffer_create();
	set_size(f, pixel_size);
	hb_buffer_clear_contents(s_buffer);
	hb_buffer_add_utf32(s_buffer, text, text_count, (unsigned int)start, count);
	hb_buffer_set_direction(s_buffer, rtl ? HB_DIRECTION_RTL : HB_DIRECTION_LTR);
	hb_buffer_set_script(s_buffer, (hb_script_t)script);
	hb_buffer_guess_segment_properties(s_buffer);
	hb_shape(f->font, s_buffer, NULL, 0);
	return (int)hb_buffer_get_length(s_buffer);
}

void st_shape_read(uint32_t *glyphs, int32_t *clusters, double *advances, double *x_offsets, double *y_offsets)
{
	unsigned int i, n = 0;
	hb_glyph_info_t *info = hb_buffer_get_glyph_infos(s_buffer, &n);
	hb_glyph_position_t *position = hb_buffer_get_glyph_positions(s_buffer, &n);
	for (i = 0; i < n; i++) {
		glyphs[i] = info[i].codepoint;
		clusters[i] = (int32_t)info[i].cluster;
		advances[i] = (double)position[i].x_advance / 64.0;
		x_offsets[i] = (double)position[i].x_offset / 64.0;
		y_offsets[i] = (double)position[i].y_offset / 64.0;
	}
}

/* ------------------------------------------------------------- fontconfig */

static int st_family_matches(FcPattern *a_font, const char *a_family)
{
	FcChar8 *l_name;
	int i;
	for (i = 0; FcPatternGetString(a_font, FC_FAMILY, i, &l_name) == FcResultMatch; i++) {
		if (strcasecmp((const char *)l_name, a_family) == 0) return 1;
	}
	return 0;
}

int st_find_font(const char *family, int weight, int italic, uint32_t code,
	char *out, int out_size, int *index, int *exact)
{
	FcPattern *l_pattern, *l_match;
	FcCharSet *l_needed = NULL;
	FcResult l_result;
	FcChar8 *l_file;
	int l_index = 0, l_found = 0;
	*exact = 0;
	*index = 0;
	if (out_size > 0) out[0] = '\0';
	if (!FcInit()) return 0;
	l_pattern = FcPatternCreate();
	if (!l_pattern) return 0;
	FcPatternAddString(l_pattern, FC_FAMILY, (const FcChar8 *)family);
	FcPatternAddInteger(l_pattern, FC_WEIGHT, FcWeightFromOpenType(weight));
	FcPatternAddInteger(l_pattern, FC_SLANT, italic ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
	if (code != 0) {
		l_needed = FcCharSetCreate();
		if (l_needed) {
			FcCharSetAddChar(l_needed, (FcChar32)code);
			FcPatternAddCharSet(l_pattern, FC_CHARSET, l_needed);
		}
	}
	FcConfigSubstitute(NULL, l_pattern, FcMatchPattern);
	FcDefaultSubstitute(l_pattern);
	l_match = FcFontMatch(NULL, l_pattern, &l_result);
	if (l_match) {
		FcCharSet *l_has;
		int l_covers = 1;
		if (code != 0 && FcPatternGetCharSet(l_match, FC_CHARSET, 0, &l_has) == FcResultMatch) {
			l_covers = FcCharSetHasChar(l_has, (FcChar32)code);
		}
		if (l_covers && FcPatternGetString(l_match, FC_FILE, 0, &l_file) == FcResultMatch
			&& (int)strlen((const char *)l_file) < out_size)
		{
			strcpy(out, (const char *)l_file);
			if (FcPatternGetInteger(l_match, FC_INDEX, 0, &l_index) == FcResultMatch) *index = l_index;
			*exact = st_family_matches(l_match, family);
			l_found = 1;
		}
		FcPatternDestroy(l_match);
	}
	if (l_needed) FcCharSetDestroy(l_needed);
	FcPatternDestroy(l_pattern);
	return l_found;
}

/* The family name stored in face 0 of `path', copied into `out'; 1 if there is one. */
int st_file_family(const char *path, char *out, int out_size)
{
	FT_Face face;
	int result = 0;
	if (out_size > 0) out[0] = '\0';
	if (!s_ft && FT_Init_FreeType(&s_ft) != 0) return 0;
	if (FT_New_Face(s_ft, path, 0, &face) != 0) return 0;
	if (face->family_name && (int)strlen(face->family_name) < out_size) {
		strcpy(out, face->family_name);
		result = 1;
	}
	FT_Done_Face(face);
	return result;
}
