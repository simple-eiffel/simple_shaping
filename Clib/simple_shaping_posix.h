/*
 * simple_shaping_posix.h - text for simple_shaping on macOS and Linux: HarfBuzz
 * shapes, FriBidi orders, FreeType and cairo draw, fontconfig finds fonts.
 * Adapted from simple_eif_phone's android_shaping (sephone_text). Owner:
 * simple_shaping_posix.c. Eiffel side: the posix/ cluster.
 * One thread: like simple_shaping itself, this is confined to its caller.
 */
#ifndef SIMPLE_SHAPING_POSIX_H
#define SIMPLE_SHAPING_POSIX_H

#include <stdint.h>

/* Bidi (UAX #9). `direction': 0 left to right, 1 right to left, 2 first strong.
   Fills `levels', one per character, and answers the paragraph level. */
int st_bidi(const uint32_t *text, int count, int direction, uint8_t *levels);

/* The script of one character, as a HarfBuzz tag. */
int st_script(uint32_t code);
int st_script_common(void);
int st_script_inherited(void);
int st_script_latin(void);

/* Fonts. `st_font_open' answers NULL if the file cannot be used. */
void *st_font_open(const char *path, int index, int weight, int italic);
int st_file_covers(const char *path, uint32_t code);   /* does the file draw `code'? */
void st_font_close(void *font);
double st_font_ascent(void *font, int pixel_size);
double st_font_descent(void *font, int pixel_size);
void *st_font_cairo_face(void *font);   /* owned by the font */

/* fontconfig: the file and face index of the best font for `family' at `weight'
   (100..900) and `italic' that draws `code' (0: any). Writes the path into `out'
   (`out_size' bytes) and the face index into `index'; sets `exact' when the font's
   own family is `family'. Answers 1 if a font was found. */
int st_find_font(const char *family, int weight, int italic, uint32_t code,
	char *out, int out_size, int *index, int *exact);

/* The family name inside a font file, as Windows would register it. */
int st_file_family(const char *path, char *out, int out_size);

/* Shaping. `st_shape' answers how many glyphs came out, in visual order, or -1.
   `st_shape_read' copies them out: `clusters' are character offsets in the item. */
int st_shape(void *font, int pixel_size, const uint32_t *text, int text_count,
	int start, int count, int rtl, int script);
void st_shape_read(uint32_t *glyphs, int32_t *clusters, double *advances, double *x_offsets, double *y_offsets);

#endif
