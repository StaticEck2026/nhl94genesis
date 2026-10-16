/*
 * audio_core.c: the Genesis sound hardware NHL '94 drives, for tools/extract/audio.py.
 *
 * Offline only. The 68000 side of the retail sound driver (p_initfx, MusicVB) runs in
 * unicorn from audio.py; this file is everything below the 68000 bus:
 *   - the Z80 (vendored superzazu/z80, MIT) running the retail Z80 driver that the 68000
 *     copies into Z80 RAM (Z80_LoadROM L63070, ROM $1AD90, $295 bytes),
 *   - the Z80 memory map: 8 KB RAM, YM2612 ports at $4000-$4003, the 9-bit bank register
 *     at $6000, the 32 KB window at $8000 onto 68000 ROM,
 *   - the YM2612 (vendored Nuked-OPN2, LGPL-2.1, discrete YM2612 mode).
 * Time base: master clock 53.693175 MHz (NTSC). Z80 = master/15, YM internal clock =
 * master/42 (one OPN2_Clock), one output sample = 24 YM clocks = master/1008 (53267 Hz).
 * So 14 Z80 cycles = 5 YM clocks exactly.
 *
 * Build: cc -O2 -shared -fPIC audio_core.c third_party/nuked_opn2/ym3438.c
 *        third_party/z80/z80.c -lm -o audio_core.so      (audio.py does this itself)
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "third_party/nuked_opn2/ym3438.h"
#include "third_party/z80/z80.h"

typedef struct {
    z80 cpu;
    ym3438_t ym;
    uint8_t ram[0x2000];
    const uint8_t *rom;
    uint32_t romsize;
    uint32_t bank;          /* 9-bit bank register: 68000 address bits 15..23 */
    uint32_t wait;          /* extra Z80 cycles owed by 68000-bus (bank window) reads */
    uint32_t bank_wait;     /* cycles per bank-window read */
    int in_reset;           /* Z80 (and YM) held in reset */
    uint32_t ym_frac;       /* Z80-cycle -> YM-clock remainder, units of 1/14 */
    int clk;                /* YM clocks into the current output sample (0..23) */
    int32_t acc_l, acc_r;
    int16_t *out;           /* interleaved L,R per 53267 Hz sample */
    uint32_t out_n, out_cap;
    uint64_t zcyc;          /* Z80 cycles elapsed (running or not) */
    /* YM write log: (sample index, port, data), for verification. */
    uint32_t *wlog;
    uint32_t wlog_n, wlog_cap;
    int log_writes;
    uint32_t psg_writes;
    uint32_t bank_reads;
} core_t;

static void push_sample(core_t *c)
{
    if (c->out_n + 1 > c->out_cap) {
        c->out_cap = c->out_cap ? c->out_cap * 2 : 1 << 16;
        c->out = (int16_t *)realloc(c->out, (size_t)c->out_cap * 2 * sizeof(int16_t));
    }
    /* Sum of 24 clocks of signed 9-bit pins: |sum| <= 24*256 = 6144; keep it as is.
     * audio.py applies one fixed gain to every file. */
    c->out[c->out_n * 2] = (int16_t)c->acc_l;
    c->out[c->out_n * 2 + 1] = (int16_t)c->acc_r;
    c->out_n++;
    c->acc_l = c->acc_r = 0;
}

static void ym_clocks(core_t *c, uint32_t zcycles)
{
    Bit16s buf[2];
    c->zcyc += zcycles;
    c->ym_frac += zcycles * 5;
    while (c->ym_frac >= 14) {
        c->ym_frac -= 14;
        OPN2_Clock(&c->ym, buf);
        c->acc_l += buf[0];
        c->acc_r += buf[1];
        if (++c->clk == 24) {
            c->clk = 0;
            push_sample(c);
        }
    }
}

static void log_write(core_t *c, uint32_t port, uint32_t data)
{
    if (!c->log_writes)
        return;
    if (c->wlog_n + 1 > c->wlog_cap) {
        c->wlog_cap = c->wlog_cap ? c->wlog_cap * 2 : 1 << 16;
        c->wlog = (uint32_t *)realloc(c->wlog, (size_t)c->wlog_cap * 2 * sizeof(uint32_t));
    }
    c->wlog[c->wlog_n * 2] = c->out_n;
    c->wlog[c->wlog_n * 2 + 1] = (port << 8) | (data & 0xFF);
    c->wlog_n++;
}

static uint8_t rd(void *ud, uint16_t a)
{
    core_t *c = (core_t *)ud;
    if (a < 0x4000)
        return c->ram[a & 0x1FFF];
    if (a < 0x6000)
        return OPN2_Read(&c->ym, a & 3);
    if (a < 0x8000)
        return 0xFF;
    {
        uint32_t addr = (c->bank << 15) | (a & 0x7FFF);
        c->wait += c->bank_wait;
        c->bank_reads++;
        return addr < c->romsize ? c->rom[addr] : 0xFF;
    }
}

static void wr(void *ud, uint16_t a, uint8_t v)
{
    core_t *c = (core_t *)ud;
    if (a < 0x4000) {
        c->ram[a & 0x1FFF] = v;
    } else if (a < 0x6000) {
        OPN2_Write(&c->ym, a & 3, v);
        /* Do not log the DAC loop's own $2A/$4001 traffic (tens of thousands a second). */
        if (!(a & 1) && v == 0x2A)
            return;
        if ((a & 3) == 1 && c->cpu.pc == 0x008C)
            return;
        log_write(c, a & 3, v);
    } else if (a < 0x6100) {
        c->bank = ((c->bank >> 1) | ((uint32_t)(v & 1) << 8)) & 0x1FF;
    } else if (a == 0x7F11) {
        c->psg_writes++;
    } else if (a >= 0x8000) {
        c->wait += c->bank_wait;
    }
}

static uint8_t pin(z80 *z, uint8_t p) { (void)z; (void)p; return 0xFF; }
static void pout(z80 *z, uint8_t p, uint8_t v) { (void)z; (void)p; (void)v; }

static void z80_reset_cpu(core_t *c)
{
    z80_init(&c->cpu);
    c->cpu.read_byte = rd;
    c->cpu.write_byte = wr;
    c->cpu.port_in = pin;
    c->cpu.port_out = pout;
    c->cpu.userdata = c;
}

core_t *core_new(const uint8_t *rom, uint32_t romsize, uint32_t bank_wait)
{
    core_t *c = (core_t *)calloc(1, sizeof(core_t));
    c->rom = rom;
    c->romsize = romsize;
    c->bank_wait = bank_wait;
    OPN2_SetChipType(ym3438_mode_ym2612);
    OPN2_Reset(&c->ym);
    z80_reset_cpu(c);
    c->in_reset = 1;
    return c;
}

void core_free(core_t *c)
{
    if (!c)
        return;
    free(c->out);
    free(c->wlog);
    free(c);
}

void core_log_writes(core_t *c, int on) { c->log_writes = on; }

/* $A11200: 0 asserts reset (the YM2612 reset line is the same on a Mega Drive),
 * $100 releases it; the Z80 then starts at $0000. */
void core_set_reset(core_t *c, int assert_reset)
{
    if (assert_reset) {
        if (!c->in_reset)
            OPN2_Reset(&c->ym);
        c->in_reset = 1;
    } else if (c->in_reset) {
        c->in_reset = 0;
        z80_reset_cpu(c);
    }
}

uint8_t core_ram_read(core_t *c, uint32_t a) { return c->ram[a & 0x1FFF]; }
void core_ram_write(core_t *c, uint32_t a, uint8_t v) { c->ram[a & 0x1FFF] = v; }
uint32_t core_pc(core_t *c) { return c->cpu.pc; }
uint64_t core_zcyc(core_t *c) { return c->zcyc; }
uint32_t core_psg_writes(core_t *c) { return c->psg_writes; }
uint32_t core_bank_reads(core_t *c) { return c->bank_reads; }

/* 68000 writes to $A04000-$A04003 (not used by NHL '94, logged if they happen). */
void core_ym_write(core_t *c, uint32_t port, uint8_t v)
{
    OPN2_Write(&c->ym, port & 3, v);
    log_write(c, (port & 3) | 0x80, v);
}

/* Run for n Z80 cycles. The Z80 executes only when not in reset and when the bus is
 * not held by the 68000 (audio.py never runs the core while it holds the bus). The YM
 * keeps clocking either way. Returns the total number of output samples so far. */
uint32_t core_run(core_t *c, uint32_t n)
{
    uint64_t end = c->zcyc + n;
    while (c->zcyc < end) {
        if (c->in_reset) {
            ym_clocks(c, (uint32_t)(end - c->zcyc));
            break;
        }
        {
            unsigned long before = c->cpu.cyc;
            uint32_t dc;
            c->wait = 0;
            z80_step(&c->cpu);
            dc = (uint32_t)(c->cpu.cyc - before) + c->wait;
            ym_clocks(c, dc);
        }
    }
    return c->out_n;
}

uint32_t core_samples(core_t *c) { return c->out_n; }

/* Copy samples [from, from+n) (interleaved L,R) into dst. */
void core_copy_samples(core_t *c, uint32_t from, uint32_t n, int16_t *dst)
{
    if (from + n > c->out_n)
        n = from < c->out_n ? c->out_n - from : 0;
    memcpy(dst, c->out + (size_t)from * 2, (size_t)n * 2 * sizeof(int16_t));
}

uint32_t core_wlog_count(core_t *c) { return c->wlog_n; }
void core_copy_wlog(core_t *c, uint32_t *dst)
{
    memcpy(dst, c->wlog, (size_t)c->wlog_n * 2 * sizeof(uint32_t));
}

/* Windowed-sinc resampler (Blackman window), mono or stereo int16 -> float. Used for
 * 53267.03 Hz -> 44100 Hz. ratio = in_rate / out_rate; cutoff relative to out Nyquist. */
void resample(const float *in, uint32_t n_in, float *out, uint32_t n_out,
              double ratio, int taps, double cutoff)
{
    const double PI = 3.14159265358979323846;
    double fc = cutoff * (ratio > 1.0 ? 1.0 / ratio : 1.0); /* in input-sample units */
    uint32_t i;
    int half = taps / 2;
    for (i = 0; i < n_out; i++) {
        double pos = i * ratio;
        long base = (long)pos;
        double frac = pos - base, acc = 0.0, wsum = 0.0;
        int k;
        for (k = -half + 1; k <= half; k++) {
            long j = base + k;
            double x = k - frac, s, w;
            if (x == 0.0)
                s = 2.0 * fc;
            else
                s = sin(2.0 * PI * fc * x) / (PI * x);
            {
                double t = (x + half) / (2.0 * half);
                if (t < 0.0 || t > 1.0)
                    w = 0.0;
                else
                    w = 0.42 - 0.5 * cos(2.0 * PI * t) + 0.08 * cos(4.0 * PI * t);
            }
            wsum += s * w;
            /* Edge extension: the chip output holds its level before and after. */
            if (j < 0)
                j = 0;
            if (j >= (long)n_in)
                j = (long)n_in - 1;
            acc += in[j] * s * w;
        }
        out[i] = (float)(wsum != 0.0 ? acc / wsum : 0.0);
    }
}

/* One-pole DC blocker in place: y[n] = x[n] - x[n-1] + r*y[n-1], starting at rest on
 * x[0] (no step at the start). Models the console's AC-coupled output. */
void dc_block(float *x, uint32_t n, double r)
{
    double px = n ? x[0] : 0.0, py = 0.0;
    uint32_t i;
    for (i = 0; i < n; i++) {
        double v = x[i];
        py = v - px + r * py;
        px = v;
        x[i] = (float)py;
    }
}

/* One-pole RC low-pass in place: y += a * (x - y), a = 1 - exp(-2 pi fc / fs). */
void one_pole(float *x, uint32_t n, double a)
{
    double y = n ? x[0] : 0.0;
    uint32_t i;
    for (i = 0; i < n; i++) {
        y += a * (x[i] - y);
        x[i] = (float)y;
    }
}
