/* Cycle-timed render of one NHL '94 sound id, for tools/extract/audio.py --engine=gpgx.
 *
 * Offline only. Drives a Genesis Plus GX libretro core (built by audio.py from a pinned
 * commit plus gpgx.patch, which adds a tap of the raw YM2612 output) without a display:
 *
 *   gpgx_render CORE ROM mkstate game|menu STATE [SHOT.ppm]
 *       game: boot, press Start until a game is under way (DoGameFrame runs) and let
 *       it play for a while. menu: boot and press Start once on the title screen (the
 *       Game Setup screen). Then, with every sound request refused, silence the chip
 *       (AllSndOff) and save the machine to STATE. SHOT gets the last frame.
 *   gpgx_render CORE ROM render STATE ID FRAMES OUT
 *       Load STATE, call sfx(ID) (ID < $30) or song(ID) at the next VBlank as the game
 *       does, refuse every other sound request, and run FRAMES frames. OUT gets the raw
 *       YM output from that VBlank on (int16 stereo, one sum of 24 YM clocks per
 *       sample, 53267 Hz) and OUT.frames the sample index of each later VBlank (uint32),
 *       the frame starts audio.py's loop and timing logic expect.
 *
 * The game keeps running underneath (68000 bus holds, DMA, the VDP), which is what sets
 * the Z80's real speed and so the DAC's pitch. */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libretro.h"
#include "types.h"
#include "m68k.h"
#include "cpuhook.h"

#define VBL_PC 0x76B2         /* VBlank handler entry */
#define SFX_PC 0x11132        /* sfx(id) */
#define SONG_PC 0x11156       /* song(id) */
#define INITFX_PC 0x1A294     /* p_initfx */
#define ALLSNDOFF_PC 0x1A264  /* AllSndOff */
#define GAMEFRAME_PC 0x794E   /* DoGameFrame */
#define MCLK_PER_SAMPLE 1008  /* 7 * 6 * 24 master clocks */

static m68ki_cpu_core *cpu;
static uint8 *wram;
static short **tap_buf;
static unsigned int *tap_n;
static int *tap_on;

static int frame;
static int press_start;      /* mkstate: Start held this frame */
static int in_game = -1;     /* mkstate: first frame DoGameFrame ran */
static int block_sound;      /* refuse p_initfx / AllSndOff */
static int pending = -1;     /* a call to make at the next VBlank: id, or -2 AllSndOff */
static int pending_song;
static int allow_once;
static int returning;        /* the injected call returns through the VBlank entry */
static unsigned int frame_tap;     /* tap samples at the start of this frame */
static long first_vbl = -1;        /* tap sample of the injection VBlank */
static uint32_t *vbl_at;           /* render: tap sample of each VBlank */
static int nvbl, vbl_cap;
static const uint16_t *video_last;
static unsigned video_w, video_h;
static size_t video_pitch;

static void w16(uint32_t a, uint16_t v) { *(uint16_t *)(wram + (a & 0xfffe)) = v; }
static uint16_t r16(uint32_t a) { return *(uint16_t *)(wram + (a & 0xfffe)); }

static void ret_now(void) {
  uint32_t sp = cpu->dar[15];
  cpu->pc = ((uint32_t)r16(sp) << 16) | r16(sp + 2);
  cpu->dar[15] = sp + 4;
}

static void hook(hook_type_t type, int width, unsigned int address, unsigned int value) {
  (void)width; (void)value;
  if (type != HOOK_M68K_E) return;
  if (address == GAMEFRAME_PC) {
    if (in_game < 0) in_game = frame;
  } else if (address == INITFX_PC) {
    if (allow_once) allow_once = 0;
    else if (block_sound) ret_now();
  } else if (address == ALLSNDOFF_PC) {
    if (allow_once) allow_once = 0;
    else if (block_sound) ret_now();
  } else if (address == VBL_PC) {
    if (returning) { returning = 0; return; }
    unsigned int at = frame_tap / 2 + (unsigned int)cpu->cycles / MCLK_PER_SAMPLE;
    if (pending != -1) {
      uint32_t sp = cpu->dar[15];
      if (pending >= 0) { sp -= 2; w16(sp, (uint16_t)pending); }
      sp -= 4; w16(sp, VBL_PC >> 16); w16(sp + 2, VBL_PC & 0xffff);
      cpu->dar[15] = sp;
      cpu->pc = pending == -2 ? ALLSNDOFF_PC : pending_song ? SONG_PC : SFX_PC;
      pending = -1;
      allow_once = 1;
      returning = 1;
      first_vbl = at;
    }
    if (first_vbl >= 0) {
      if (nvbl == vbl_cap) { vbl_cap = vbl_cap ? 2 * vbl_cap : 4096; vbl_at = realloc(vbl_at, vbl_cap * 4); }
      vbl_at[nvbl++] = at - (unsigned int)first_vbl;
    }
  }
}

static bool env(unsigned cmd, void *data) {
  switch (cmd) {
  case RETRO_ENVIRONMENT_GET_VARIABLE: {
    struct retro_variable *v = data;
    v->value = NULL;
    if (!strcmp(v->key, "genesis_plus_gx_ym2612")) v->value = "nuked (ym2612)";
    else if (!strcmp(v->key, "genesis_plus_gx_audio_filter")) v->value = "disabled";
    else if (!strcmp(v->key, "genesis_plus_gx_sound_output")) v->value = "stereo";
    else if (!strcmp(v->key, "genesis_plus_gx_region_detect")) v->value = "ntsc-u";
    else if (!strcmp(v->key, "genesis_plus_gx_bram")) v->value = "per game";
    return v->value != NULL;
  }
  case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
  case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
    *(const char **)data = "."; return true;
  case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: return *(const unsigned *)data == RETRO_PIXEL_FORMAT_RGB565;
  case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *(bool *)data = false; return true;
  default: return false;
  }
}
static void video(const void *d, unsigned w, unsigned h, size_t p) {
  if (d) { video_last = d; video_w = w; video_h = h; video_pitch = p; }
}
static void audio1(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audiob(const int16_t *d, size_t n) { (void)d; return n; }
static void poll(void) {}
static int16_t input(unsigned port, unsigned dev, unsigned idx, unsigned id) {
  (void)dev; (void)idx;
  return port == 0 && id == RETRO_DEVICE_ID_JOYPAD_START && press_start;
}

static void shot(const char *path) {
  FILE *f = fopen(path, "wb");
  if (!f || !video_last) { if (f) fclose(f); return; }
  fprintf(f, "P6\n%u %u\n255\n", video_w, video_h);
  for (unsigned y = 0; y < video_h; y++)
    for (unsigned x = 0; x < video_w; x++) {
      uint16_t c = ((const uint16_t *)((const uint8_t *)video_last + y * video_pitch))[x];
      uint8_t rgb[3] = {(uint8_t)((c >> 11) << 3), (uint8_t)(((c >> 5) & 63) << 2), (uint8_t)((c & 31) << 3)};
      fwrite(rgb, 1, 3, f);
    }
  fclose(f);
}

static void *load(const char *path, long *size) {
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); exit(1); }
  fseek(f, 0, SEEK_END); *size = ftell(f); fseek(f, 0, SEEK_SET);
  void *b = malloc(*size);
  if (fread(b, 1, *size, f) != (size_t)*size) { perror(path); exit(1); }
  fclose(f);
  return b;
}

static void (*run)(void);

static void step(void) {
  frame_tap = *tap_n;
  run();
  frame++;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: gpgx_render CORE ROM mkstate game|menu STATE [SHOT.ppm]\n"
                    "       gpgx_render CORE ROM render STATE ID FRAMES OUT\n");
    return 2;
  }
  void *h = dlopen(argv[1], RTLD_NOW);
  if (!h) { fprintf(stderr, "%s\n", dlerror()); return 1; }
#define SYM(n) typeof(&n) p_##n = dlsym(h, #n)
  SYM(retro_set_environment); SYM(retro_set_video_refresh); SYM(retro_set_audio_sample);
  SYM(retro_set_audio_sample_batch); SYM(retro_set_input_poll); SYM(retro_set_input_state);
  SYM(retro_init); SYM(retro_load_game); SYM(retro_run); SYM(retro_serialize_size);
  SYM(retro_serialize); SYM(retro_unserialize); SYM(retro_get_memory_data);
  SYM(retro_get_memory_size); SYM(set_cpu_hook);
  cpu = dlsym(h, "m68k");
  wram = dlsym(h, "work_ram");
  tap_buf = dlsym(h, "gpgx_tap_buf");
  tap_n = dlsym(h, "gpgx_tap_n");
  tap_on = dlsym(h, "gpgx_tap_on");
  if (!cpu || !wram || !tap_buf || !tap_n || !tap_on || !p_set_cpu_hook) {
    fprintf(stderr, "core lacks the gpgx.patch exports\n");
    return 1;
  }
  run = p_retro_run;
  p_retro_set_environment(env); p_retro_set_video_refresh(video); p_retro_set_audio_sample(audio1);
  p_retro_set_audio_sample_batch(audiob); p_retro_set_input_poll(poll); p_retro_set_input_state(input);
  p_retro_init();
  long rom_size;
  void *rom = load(argv[2], &rom_size);
  struct retro_game_info gi = {argv[2], rom, (size_t)rom_size, NULL};
  if (!p_retro_load_game(&gi)) { fprintf(stderr, "load failed\n"); return 1; }
  p_set_cpu_hook(hook);
  size_t ssize = p_retro_serialize_size();
  /* The battery RAM is not in a GPGX state; the front end reads it, so it goes after. */
  uint8_t *sram = p_retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
  size_t sram_size = p_retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
  *tap_on = 1;

  if (!strcmp(argv[3], "mkstate") && argc >= 6) {
    int quiet_at;
    if (!strcmp(argv[4], "menu")) {
      /* The title screen is up (its song starts near frame 1037). */
      for (frame = 0; frame < 1300; ) {
        press_start = frame >= 1100 && frame < 1103;
        block_sound = frame >= 1103;
        step();
      }
      quiet_at = 1300;
    } else {
      /* Start, a few frames at a time, until play begins (title, Game Setup, the
       * team screens and the opening faceoff all take Start). */
      for (frame = 0; in_game < 0 || frame < in_game + 1; ) {
        press_start = in_game < 0 && frame >= 1100 && frame % 45 < 3;
        step();
        if (frame > 20000) { fprintf(stderr, "no game after %d frames\n", frame); return 1; }
      }
      press_start = 0;
      block_sound = 1;
      while (frame < in_game + 900) step();
      quiet_at = in_game + 900;
    }
    pending = -2;
    while (frame < quiet_at + 300) step();
    /* The chip must be silent now. */
    unsigned int quiet_from = frame_tap;
    step();
    int peak = 0;
    for (unsigned int i = quiet_from; i < *tap_n; i++) {
      int v = abs((*tap_buf)[i]);
      if (v > peak) peak = v;
    }
    void *st = malloc(ssize);
    if (!p_retro_serialize(st, ssize)) { fprintf(stderr, "serialize failed\n"); return 1; }
    FILE *f = fopen(argv[5], "wb");
    fwrite(st, 1, ssize, f);
    if (sram_size) fwrite(sram, 1, sram_size, f);
    fclose(f);
    if (argc > 6) shot(argv[6]);
    printf("in_game %d saved %d peak %d\n", in_game, frame, peak);
    return 0;
  }
  if (!strcmp(argv[3], "render") && argc >= 8) {
    long n;
    void *st = load(argv[4], &n);
    if ((size_t)n != ssize + sram_size || !p_retro_unserialize(st, ssize)) {
      fprintf(stderr, "bad state\n");
      return 1;
    }
    if (sram_size) memcpy(sram, (uint8_t *)st + ssize, sram_size);
    int id = (int)strtol(argv[5], NULL, 0), frames = atoi(argv[6]);
    block_sound = 1;
    *tap_n = 0;
    pending = id;
    pending_song = id >= 0x30;
    frame = 0;
    while (nvbl <= frames && frame < frames + 600) step();
    if (first_vbl < 0) { fprintf(stderr, "no VBlank\n"); return 1; }
    unsigned int end = vbl_at[nvbl - 1] + (unsigned int)first_vbl;
    FILE *o = fopen(argv[7], "wb");
    fwrite(*tap_buf + 2 * first_vbl, 4, end - (unsigned int)first_vbl, o);
    fclose(o);
    char path[4096];
    snprintf(path, sizeof path, "%s.frames", argv[7]);
    o = fopen(path, "wb");
    fwrite(vbl_at, 4, nvbl, o);
    fclose(o);
    return 0;
  }
  fprintf(stderr, "bad mode\n");
  return 2;
}
