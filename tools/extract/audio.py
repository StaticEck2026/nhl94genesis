#!/usr/bin/env python3
"""Render NHL '94 (Genesis) sound effects and music to loose WAV files for the Godot port.

Offline only. The game never emulates or reads the ROM at runtime; it plays what this
writes. Usage:

    python3 tools/extract/audio.py [lst/nhl94.bin] [godot/assets/audio] [--ids=0,1,0x78]
                                   [--verify] [--engine=gpgx|unicorn] [--filter=model1|none]
                                   [--crowd]

--ids renders only those ids and merges them into an existing audio.json (add --crowd to
redo the crowd noise too). --verify also logs the Z80's YM writes and records PSG /
direct-YM write counts per id. GPGX_SRC=<checkout> builds GPGX from a local clone.

How: the retail sound code itself runs here. The 68000 half (p_initfx L61549, MusicVB
L61792 and everything they call) runs in unicorn (pip install unicorn==2.1.4); the Z80
half (the $295-byte driver at ROM $1AD90 that Z80_LoadROM copies to Z80 RAM) runs on a
vendored Z80 core, and the YM2612 is Nuked-OPN2, both in audio_core.c, which this script
compiles with the system C compiler (cc) on first use. Each id is rendered from a cold
boot (Z80_LoadROM, AllSndOff, MusicVB, as Begin does), then p_initfx(id) and one MusicVB
per NTSC frame, with the Z80 and YM clocked from the 53.693175 MHz master clock. That
render gives the sequence events, loop frames and length.

--engine=gpgx (default) then takes the samples from Genesis Plus GX, built at run time
from a pinned commit, running the whole game: the same id started at a VBlank of a game
in progress (the menu songs: on the Game Setup screen), so 68000 bus holds and VDP DMA
slow the Z80 as on the console (the DAC's pitch). --engine=unicorn keeps the unicorn
render's samples (no network needed). --filter=model1 (default) applies the Model 1
output low-pass (first-order, 3390 Hz); --filter=none leaves the chip output as is. The
crowd noise (PSG, which the driver never uses) is rendered to crowd_noise.wav.

Output (docs/specs/audio.md):
  sfx/sfx_XX.wav     ids $00..$2F (XX = lower-case hex, as SfxBank loads them)
  music/song_XX.wav  ids $30..$7A, plus $0B $0C $0D $0F (crowd cues the game starts with
                     song(); same render as the sfx file)
  crowd_noise.wav    the PSG crowd noise at full volume, one LFSR period, looped
  audio.json         per id: duration, loop points, voices used, priority/channel info

Format: 44100 Hz, 16-bit, mono (every retail patch pans centre; L == R is checked and
recorded as "stereo" in audio.json).
One fixed gain for every file, so relative levels are retail. The Model 1 low-pass and a
5 Hz DC blocker model the console's output stage (the DAC holds its last value between
samples). Looping songs carry a RIFF 'smpl' loop (Godot's WAV importer reads it) and
loop_start/loop_end in audio.json. Deterministic: same ROM, same bytes.
"""
import ctypes
import hashlib
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROM_CRC = 0x9438F5DD

# Clocks (NTSC). One frame = 262 lines * 3420 master clocks.
MASTER = 53693175.0
Z80_PER_FRAME = 262 * 3420 // 15          # 59736 Z80 cycles
YM_RATE = MASTER / 7.0 / 144.0             # 53267.03 Hz, one OPN2 output sample
MCLK_PER_YM_SAMPLE = 7 * 144
FRAME_HZ = MASTER / (262 * 3420)           # 59.9227 Hz
OUT_RATE = 44100
# Z80 cycles lost per read through the $8000 bank window (68000 bus arbitration). The
# exact figure varies (about 3 to 4 on hardware); it only nudges the DAC sample rate.
BANK_WAIT = 3
# Z80 cycles granted each time the 68000 releases the Z80 bus inside a routine (the
# sub_1A574 retry loop spins `dbf` 100 times, about 1000 68000 cycles).
RELEASE_RUN = 470
# Output scale: OPN2 sum of 24 clocks of signed 9-bit pins (|x| <= 6144) -> int16.
GAIN = 6.0
# The console's analog output filter (--filter). "model1": a first-order RC low-pass at
# 3390 Hz, BlastEm's model of a Model 1 Mega Drive (default.cfg lowpass_cutoff, applied
# as rc = 1 / (2 pi fc)). "none": the chip's output as is.
FILTERS = {"model1": 3390.0, "none": None}

# 68000 entry points (checked against the ROM bytes at start-up).
A_ALLSNDOFF = 0x1A264     # L61530
A_P_INITFX = 0x1A294      # L61549
A_MUSICVB = 0x1A50A       # L61792
A_Z80_LOADROM = 0x1ACC2   # L63070
A_EVENT = 0x1A5CE         # sub_1A5C0: movea.l (a5),a0  (an event is about to run)
A_JUMP = 0x1A5EE          # sub_1A5C0: move.l 2(a0),(a5)  (a sequence loops)
SEQ_TABLE = 0x2C648       # unk_2C648: 123 longs, id -> sequence
PATCHES = 0x2C248         # FM patches, 32 bytes each
SLOTS = 0xFFD3D4          # 8 sequence slots x 6 bytes {long ptr, word counter}
VOICES = 0xFFD3A4         # 6 voice records x 8 bytes
SENTINEL = 0x3FFFF0
MUSIC_FIRST = 0x2CEF2     # sub_1A304: a slot pointer >= this is "music"

ENTRY_BYTES = {A_ALLSNDOFF: "48e7ffe0", A_P_INITFX: "b07c007a", A_MUSICVB: "6100fe64",
               A_Z80_LOADROM: "48e7e0e0", A_EVENT: "2055", A_JUMP: "2aa80002"}


# ---------------------------------------------------------------------------- C core

def build_core():
    srcs = [os.path.join(HERE, "audio_core.c"),
            os.path.join(HERE, "third_party", "nuked_opn2", "ym3438.c"),
            os.path.join(HERE, "third_party", "z80", "z80.c")]
    h = hashlib.sha256()
    for s in srcs + [os.path.join(HERE, "third_party", "nuked_opn2", "ym3438.h"),
                     os.path.join(HERE, "third_party", "z80", "z80.h")]:
        h.update(open(s, "rb").read())
    so = os.path.join(tempfile.gettempdir(), "nhl94_audio_core_%s.so" % h.hexdigest()[:16])
    if not os.path.exists(so):
        cc = os.environ.get("CC", "cc")
        tmp = so + ".%d.tmp" % os.getpid()
        subprocess.check_call([cc, "-O2", "-shared", "-fPIC", "-I", HERE] + srcs +
                              ["-lm", "-o", tmp])
        os.replace(tmp, so)
    lib = ctypes.CDLL(so)
    P, U8, U32, U64, I = ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32, ctypes.c_uint64, ctypes.c_int
    sig = {
        "core_new": (P, [ctypes.c_char_p, U32, U32]),
        "core_free": (None, [P]),
        "core_log_writes": (None, [P, I]),
        "core_set_reset": (None, [P, I]),
        "core_ram_read": (U8, [P, U32]),
        "core_ram_write": (None, [P, U32, U8]),
        "core_ym_write": (None, [P, U32, U8]),
        "core_run": (U32, [P, U32]),
        "core_samples": (U32, [P]),
        "core_copy_samples": (None, [P, U32, U32, P]),
        "core_wlog_count": (U32, [P]),
        "core_copy_wlog": (None, [P, P]),
        "core_pc": (U32, [P]),
        "core_zcyc": (U64, [P]),
        "core_psg_writes": (U32, [P]),
        "core_bank_reads": (U32, [P]),
        "resample": (None, [P, U32, P, U32, ctypes.c_double, I, ctypes.c_double]),
        "dc_block": (None, [P, U32, ctypes.c_double]),
        "one_pole": (None, [P, U32, ctypes.c_double]),
    }
    for name, (res, args) in sig.items():
        f = getattr(lib, name)
        f.restype = res
        f.argtypes = args
    return lib


# ---------------------------------------------------------------------------- GPGX engine
#
# --engine=gpgx (the default) renders the sound inside a real game in progress on Genesis
# Plus GX, a cycle-timed Mega Drive emulator: the 68000's Z80-bus holds and the VDP's DMA
# stalls slow the Z80 driver exactly as on the console, which sets the DAC's pitch and
# timing. The FM is the same Nuked-OPN2 YM2612 either way. GPGX's own licence forbids
# commercial use, so nothing of it is vendored or shipped: audio.py fetches the pinned
# commit, makes the three small edits below (a tap of the raw YM output before GPGX's
# resampler, two exports) and builds it, at extraction time only. gpgx_render.c is the
# headless front end. The game then gets only the rendered files.

GPGX_URL = "https://github.com/libretro/Genesis-Plus-GX"
GPGX_COMMIT = "aa74d79634cd230f65cce4180e92688e53883d2f"
GPGX_TAP = """
/* NHL94 port (tools/extract/audio.py): a tap of the raw YM output, one stereo sum of
 * 24 YM clocks per sample (53267 Hz), before any resampling. */
short *gpgx_tap_buf = NULL;
unsigned int gpgx_tap_n = 0, gpgx_tap_cap = 0;
int gpgx_tap_on = 0;
static void gpgx_tap(int l, int r)
{
  if (!gpgx_tap_on) return;
  if (gpgx_tap_n + 2 > gpgx_tap_cap)
  {
    gpgx_tap_cap = gpgx_tap_cap ? gpgx_tap_cap * 2 : (1 << 20);
    gpgx_tap_buf = (short *)realloc(gpgx_tap_buf, gpgx_tap_cap * sizeof(short));
  }
  gpgx_tap_buf[gpgx_tap_n++] = (short)l;
  gpgx_tap_buf[gpgx_tap_n++] = (short)r;
}
"""


def _gpgx_edit(path, old, new):
    s = open(path, "rb").read().decode("latin-1")
    crlf = "\r\n" in s
    s = s.replace("\r\n", "\n")
    if new in s:
        return
    assert s.count(old) == 1, (path, old)
    s = s.replace(old, new)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(path, "wb").write(s.encode("latin-1"))


def build_gpgx():
    """Fetch, edit and build the pinned GPGX core and gpgx_render. Returns (core, exe).
    GPGX_SRC=<checkout of GPGX_COMMIT> skips the download."""
    h = hashlib.sha256()
    h.update(open(os.path.join(HERE, "gpgx_render.c"), "rb").read())
    h.update(GPGX_TAP.encode())
    root = os.path.join(tempfile.gettempdir(), "nhl94_gpgx_%s_%s" % (GPGX_COMMIT[:10],
                                                                      h.hexdigest()[:12]))
    src = os.path.join(root, "gpgx")
    core = os.path.join(src, "genesis_plus_gx_libretro.so")
    exe = os.path.join(root, "gpgx_render")
    if os.path.exists(core) and os.path.exists(exe):
        return core, exe
    os.makedirs(root, exist_ok=True)
    if not os.path.exists(src):
        if os.environ.get("GPGX_SRC"):
            subprocess.check_call(["cp", "-r", os.environ["GPGX_SRC"], src])
        else:
            subprocess.check_call(["git", "clone", "-q", GPGX_URL, src])
        subprocess.check_call(["git", "-C", src, "checkout", "-q", "-f", GPGX_COMMIT])
        subprocess.check_call(["git", "-C", src, "clean", "-q", "-fdx"])
    _gpgx_edit(os.path.join(src, "core", "debug", "cpuhook.h"),
               "\nvoid (*cpu_hook)(", "\nextern void (*cpu_hook)(")
    _gpgx_edit(os.path.join(src, "libretro", "link.T"),
               "global: retro_*;",
               "global: retro_*; set_cpu_hook; m68k; work_ram; gpgx_tap_buf; gpgx_tap_n; "
               "gpgx_tap_on;")
    snd = os.path.join(src, "core", "sound", "sound.c")
    _gpgx_edit(snd, "#ifdef HAVE_YM3438_CORE\nstatic void YM3438_Update(",
               "#ifdef HAVE_YM3438_CORE\n" + GPGX_TAP + "\nstatic void YM3438_Update(")
    _gpgx_edit(snd, "        ym3438_sample[1] += ym3438_accm[j][1];\n      }\n",
               "        ym3438_sample[1] += ym3438_accm[j][1];\n      }\n"
               "      gpgx_tap(ym3438_sample[0], ym3438_sample[1]);\n")
    jobs = str(os.cpu_count() or 2)
    subprocess.check_call(["make", "-s", "-C", src, "-f", "Makefile.libretro", "-j" + jobs,
                           "HOOK_CPU=1"], stdout=subprocess.DEVNULL)
    cc = os.environ.get("CC", "cc")
    subprocess.check_call([cc, "-O2", "-o", exe, os.path.join(HERE, "gpgx_render.c"),
                           "-I" + os.path.join(src, "libretro", "libretro-common", "include"),
                           "-I" + os.path.join(src, "core"),
                           "-I" + os.path.join(src, "core", "m68k"),
                           "-I" + os.path.join(src, "core", "debug"),
                           "-DLSB_FIRST", "-DHOOK_CPU", "-DM68K_OVERCLOCK_SHIFT=20",
                           "-DZ80_OVERCLOCK_SHIFT=20", "-DINLINE=static inline", "-ldl"])
    return core, exe


# Where the game plays each id: the three menu songs on the menu screens (title, Game
# Setup / Matchups, intermission), everything else during play. The machine's load
# differs (in play the VDP's DMA stalls the Z80 more: about 1.5% lower DAC pitch).
MENU_IDS = (0x78, 0x79, 0x7A)


class Gpgx:
    """Saved machine states (a game in progress, the Game Setup screen), and renders
    from them."""

    def __init__(self, rom_path):
        self.core, self.exe = build_gpgx()
        self.rom = os.path.abspath(rom_path)
        self.dir = os.path.dirname(self.exe)
        self.states = {}
        for kind in ("game", "menu"):
            st = os.path.join(self.dir, kind + ".state")
            if not os.path.exists(st):
                out = subprocess.check_output([self.exe, self.core, self.rom, "mkstate", kind,
                                               st + ".tmp",
                                               os.path.join(self.dir, kind + ".ppm")],
                                              text=True)
                os.replace(st + ".tmp", st)
                sys.stderr.write("gpgx %s state: %s" % (kind, out))
            self.states[kind] = st

    @staticmethod
    def context(sid):
        return "menu" if sid in MENU_IDS else "game"

    def render(self, sid, frames):
        """Raw YM output from the VBlank that starts sid, for `frames` frames: (int16
        stereo array, n, sample index of each VBlank)."""
        import numpy as np
        out = os.path.join(self.dir, "render_%02x.raw" % sid)
        subprocess.check_call([self.exe, self.core, self.rom, "render",
                               self.states[self.context(sid)], str(sid), str(frames), out])
        raw = np.fromfile(out, dtype="<i2")
        fs = np.fromfile(out + ".frames", dtype="<u4").tolist()
        os.remove(out)
        os.remove(out + ".frames")
        return raw, len(raw) // 2, fs


# ---------------------------------------------------------------------------- 68000 side

def import_unicorn():
    try:
        import unicorn  # noqa: F401
    except ImportError:
        sys.exit("audio.py needs unicorn (pip install unicorn==2.1.4) to run the retail "
                 "68000 sound driver.")
    import unicorn
    from unicorn import m68k_const
    return unicorn, m68k_const


class Machine:
    """A cold Genesis: 68000 (unicorn) running the retail driver, Z80 + YM in the C core."""

    def __init__(self, lib, rom, uc_mod, mk, log_writes=False):
        self.lib, self.rom, self.uc_mod, self.mk = lib, rom, uc_mod, mk
        self._rom_c = ctypes.create_string_buffer(rom, len(rom))
        self.core = lib.core_new(self._rom_c, len(rom), BANK_WAIT)
        lib.core_log_writes(self.core, 1 if log_writes else 0)
        Uc = uc_mod.Uc
        u = self.u = Uc(uc_mod.UC_ARCH_M68K, uc_mod.UC_MODE_BIG_ENDIAN)
        u.ctl_set_cpu_model(mk.UC_CPU_M68K_M68000)
        u.mem_map(0, 0x400000)
        u.mem_write(0, rom)
        self.ram = ctypes.create_string_buffer(0x10000)
        u.mem_map_ptr(0xFF0000, 0x10000, uc_mod.UC_PROT_ALL, self.ram)
        u.mem_map_ptr(0xFFFF0000, 0x10000, uc_mod.UC_PROT_ALL, self.ram)
        u.mmio_map(0xA00000, 0x10000, self._zr, None, self._zw, None)
        u.mmio_map(0xA10000, 0x1000, self._ior, None, self._iow, None)
        u.mmio_map(0xA11000, 0x1000, self._cr, None, self._cw, None)
        u.mmio_map(0xC00000, 0x1000, self._vr, None, self._vw, None)
        self.busreq = False
        self.frame = 0
        self.zwrites = []          # 68000 writes into Z80 RAM: (frame, addr, value)
        self.psg68k = 0
        self.ym68k = 0
        self.jumps = []            # (frame, slot address, target)
        self.events = []           # (frame, slot address, event address)
        u.hook_add(uc_mod.UC_HOOK_CODE, self._hook_jump, None, A_JUMP, A_JUMP)
        u.hook_add(uc_mod.UC_HOOK_CODE, self._hook_event, None, A_EVENT, A_EVENT)
        self.frame_samples = []    # core sample index at each frame start

    def free(self):
        self.lib.core_free(self.core)
        self.core = None

    # Hooks
    def _hook_jump(self, uc, addr, size, ud):
        a0 = uc.reg_read(self.mk.UC_M68K_REG_A0)
        a5 = uc.reg_read(self.mk.UC_M68K_REG_A5)
        tgt = struct.unpack(">I", self.rom[a0 + 2:a0 + 6])[0]
        self.jumps.append((self.frame, a5 & 0xFFFFFF, tgt))

    def _hook_event(self, uc, addr, size, ud):
        a5 = uc.reg_read(self.mk.UC_M68K_REG_A5)
        ptr = self.r32(a5)
        self.events.append((self.frame, a5 & 0xFFFFFF, ptr))

    # Memory-mapped I/O
    def _zr(self, uc, off, size, ud):
        v = 0
        for i in range(size):
            a = (off + i) & 0xFFFF
            b = self.lib.core_ram_read(self.core, a) if a < 0x4000 else 0
            v = (v << 8) | b
        return v

    def _zw(self, uc, off, size, val, ud):
        for i in range(size):
            a = (off + i) & 0xFFFF
            b = (val >> (8 * (size - 1 - i))) & 0xFF
            if a < 0x4000:
                self.lib.core_ram_write(self.core, a, b)
                self.zwrites.append((self.frame, a, b))
            elif a < 0x6000:
                self.lib.core_ym_write(self.core, a & 3, b)
                self.ym68k += 1

    def _ior(self, uc, off, size, ud):
        if off in (3, 5):
            return 0x7F        # no buttons
        if off == 1:
            return 0xA0        # overseas NTSC
        return 0

    def _iow(self, uc, off, size, val, ud):
        pass

    def _cr(self, uc, off, size, ud):
        if 0x100 <= off < 0x102:
            # BUSACK: bit 0 of byte $A11100 is 0 once the bus is granted.
            v = 0 if self.busreq else 1
            return (v << 8) if size == 2 and off == 0x100 else v
        return 0

    def _cw(self, uc, off, size, val, ud):
        if off == 0x100:
            req = bool((val >> 8) & 1) if size == 2 else bool(val & 1)
            if self.busreq and not req:
                self.busreq = False
                self.lib.core_run(self.core, RELEASE_RUN)
            self.busreq = req
        elif off == 0x200:
            rel = bool((val >> 8) & 1) if size == 2 else bool(val & 1)
            self.lib.core_set_reset(self.core, 0 if rel else 1)

    def _vr(self, uc, off, size, ud):
        return 0

    def _vw(self, uc, off, size, val, ud):
        if off in (0x10, 0x11, 0x12, 0x13):
            self.psg68k += 1

    # Helpers
    def r32(self, a):
        a &= 0xFFFF
        return struct.unpack(">I", self.ram.raw[a:a + 4])[0]

    def r16(self, a):
        a &= 0xFFFF
        return struct.unpack(">H", self.ram.raw[a:a + 2])[0]

    def call(self, addr, d0=None):
        mk = self.mk
        sp = 0xFFFFFF00
        self.u.mem_write(sp - 4, struct.pack(">I", SENTINEL))
        self.u.reg_write(mk.UC_M68K_REG_SR, 0x2700)
        self.u.reg_write(mk.UC_M68K_REG_A7, sp - 4)
        if d0 is not None:
            self.u.reg_write(mk.UC_M68K_REG_D0, d0)
        self.u.emu_start(addr, SENTINEL, 0, 5000000)
        if self.u.reg_read(mk.UC_M68K_REG_PC) != SENTINEL:
            raise RuntimeError("68000 routine $%X did not return" % addr)

    def run_frame(self, with_musicvb=True):
        """One NTSC frame: MusicVB at VBlank, then the rest of the frame on the Z80."""
        self.frame_samples.append(self.lib.core_samples(self.core))
        if with_musicvb:
            self.call(A_MUSICVB)
        self.busreq = False
        end = (self.frame + 1) * Z80_PER_FRAME
        now = self.lib.core_zcyc(self.core)
        if now < end:
            self.lib.core_run(self.core, end - now)
        self.frame += 1

    def boot(self):
        """Begin (L29715): Z80_LoadROM, AllSndOff, MusicVB; then let the Z80 settle."""
        self.call(A_Z80_LOADROM)
        self.call(A_ALLSNDOFF)
        self.run_frame()
        self.run_frame()

    def slots(self):
        return [self.r32(SLOTS + 6 * i) for i in range(8)]

    def samples(self, start=0):
        n = self.lib.core_samples(self.core) - start
        buf = (ctypes.c_int16 * (2 * max(n, 0)))()
        if n > 0:
            self.lib.core_copy_samples(self.core, start, n, buf)
        return buf, n


# ---------------------------------------------------------------------------- sequences

def u32(rom, a):
    return struct.unpack(">I", rom[a:a + 4])[0]


DAC_FREQ = 0x1A890        # unk_1A890: 12 words, the DAC step per semitone at octave 8
DAC_TABLE = 0x1B01C       # unk_1B01C: 15 x {long address, long next}, instruments $60..$6E


def dac_step(rom, note):
    """sub_1A7D8 for a DAC instrument without pitch bend: the byte written to Z80 $8E."""
    octave, semi = divmod(note, 12)
    f = struct.unpack(">H", rom[DAC_FREQ + 2 * semi:DAC_FREQ + 2 * semi + 2])[0]
    sh = (8 - octave) & 63
    return (f >> sh if sh < 16 else 0) & 0xFF


def dac_rate(step):
    """Output rate of the Z80 loop: one sample byte per 117 + BANK_WAIT cycles x step/256."""
    return MASTER / 15.0 / (117 + BANK_WAIT) * step / 256.0


def scan_sequence(rom, sid, limit=200000):
    """Walk a sequence statically: channels, instruments, notes, end kind, tick length,
    DAC notes and FM polyphony. Follows the format sub_1A5C0 implements (docs/specs/audio.md
    section 3). Ticks are MusicVB calls (NTSC frames); tick 0 is the first MusicVB."""
    start = u32(rom, SEQ_TABLE + 4 * sid)
    p = start
    tick = rom[p]
    instr = {}
    info = {"start": start, "fm_instruments": set(), "dac_instruments": set(),
            "channels": set(), "notes": 0, "end": None, "loop_target": None,
            "ticks": 0, "events": 0, "dac": [], "fm_max_voices": 0}
    on = {}          # (ch, note) -> (tick, instr, velocity)
    first = True
    n = 0
    while n < limit:
        n += 1
        if not first:
            tick += rom[p]
        first = False
        st, d1, d2 = rom[p + 1], rom[p + 2], rom[p + 3]
        if st == 0:
            if rom[p + 2] & 0x80:
                info["end"] = "end"
            else:
                info["end"] = "loop"
                info["loop_target"] = u32(rom, p + 2)
            break
        ch = st & 0xF
        kind = st >> 4
        if kind in (8, 9, 0xB, 0xC, 0xE):
            info["channels"].add(ch)
        if kind == 0xC:
            instr[ch] = d1
        elif kind == 9 and d2:
            info["notes"] += 1
            ins = instr.get(ch, 0)
            (info["dac_instruments"] if ins >= 0x60 else info["fm_instruments"]).add(ins)
            on[(ch, d1)] = (tick, ins, d2)
            info["fm_max_voices"] = max(info["fm_max_voices"],
                                        sum(1 for v in on.values() if v[1] < 0x60))
        elif kind == 8 or (kind == 9 and not d2):
            v = on.pop((ch, d1), None)
            if v and v[1] >= 0x60:
                info["dac"].append({"instr": v[1], "note": d1, "velocity": v[2],
                                    "on_tick": v[0], "off_tick": tick})
        p += 4
    for (ch, note), v in on.items():
        if v[1] >= 0x60:
            info["dac"].append({"instr": v[1], "note": note, "velocity": v[2],
                                "on_tick": v[0], "off_tick": None})
    info["dac"].sort(key=lambda d: d["on_tick"])
    info["ticks"] = tick
    info["events"] = n
    for k in ("fm_instruments", "dac_instruments", "channels"):
        info[k] = sorted(info[k])
    return info


# ---------------------------------------------------------------------------- render

def render(lib, rom, uc_mod, mk, sid, max_frames, log_writes=False, tail_frames=180,
           loop_extra_frames=240):
    """Render one id from a cold boot. Returns a dict with native-rate stereo samples."""
    m = Machine(lib, rom, uc_mod, mk, log_writes=log_writes)
    m.boot()
    m.zwrites.clear()
    m.jumps.clear()
    m.events.clear()
    m.frame_samples.clear()
    base_frame = m.frame
    s0 = lib.core_samples(m.core)
    m.call(A_P_INITFX, sid)
    slot_addrs = [SLOTS + 6 * i for i in range(8)]
    start_ptr = u32(rom, SEQ_TABLE + 4 * sid)
    my_slot = None
    for a in slot_addrs:
        if m.r32(a) == start_ptr:
            my_slot = a
    ended_at = None
    loop_frames = []
    quiet = 0
    while m.frame - base_frame < max_frames:
        m.run_frame()
        f = m.frame - base_frame
        if m.jumps:
            loop_frames = [j[0] - base_frame for j in m.jumps]
            if len(loop_frames) == 1 and ended_at is None:
                ended_at = f
        if ended_at is None and all(s & 0x80000000 for s in m.slots()):
            ended_at = f
        if ended_at is not None:
            if loop_frames:
                if f >= loop_frames[0] + loop_extra_frames:
                    break
                continue
            # Sequence over: wait for the voices to die away (two quiet frames).
            buf, n = m.samples(m.frame_samples[-1])
            seg = buf[0:2 * n:2]
            if n and max(seg) - min(seg) <= 4:
                quiet += 1
            else:
                quiet = 0
            if quiet >= 2 or f >= ended_at + tail_frames:
                break
    buf, n = m.samples(s0)
    res = {
        "id": sid,
        "slot": my_slot,
        "native": buf,
        "n": n,
        "frames": m.frame - base_frame,
        "end_frame": ended_at,
        "loop_frames": loop_frames,
        "jumps": [(j[0] - base_frame, j[1], j[2]) for j in m.jumps],
        "events": [(e[0] - base_frame, e[1], e[2]) for e in m.events],
        "frame_samples": [x - s0 for x in m.frame_samples],
        "zwrites": [(w[0] - base_frame, w[1], w[2]) for w in m.zwrites],
        "psg_writes": lib.core_psg_writes(m.core) + m.psg68k,
        "ym68k": m.ym68k,
    }
    if log_writes:
        cnt = lib.core_wlog_count(m.core)
        wl = (ctypes.c_uint32 * (2 * cnt))()
        lib.core_copy_wlog(m.core, wl)
        res["ymlog"] = [(wl[2 * i] - s0, wl[2 * i + 1] >> 8, wl[2 * i + 1] & 0xFF)
                        for i in range(cnt)]
    m.free()
    return res


DC_HZ = 5.0
XFADE = 441                # 10 ms crossfade into the loop seam


def to_output(lib, native, n, lowpass_hz=None):
    """Native stereo int16 (53267 Hz) -> mono float32 at OUT_RATE: the console's output
    low-pass (lowpass_hz, None for none), resampling, DC blocking."""
    import numpy as np
    st = np.frombuffer(bytes(native), dtype=np.int16, count=2 * n).reshape(-1, 2)
    stereo = bool(np.any(st[:, 0] != st[:, 1]))
    mono = (st.astype(np.float32).mean(axis=1) if stereo else st[:, 0].astype(np.float32))
    return mono_to_output(lib, mono, lowpass_hz), stereo


def mono_to_output(lib, mono, lowpass_hz):
    import numpy as np
    mono = np.ascontiguousarray(mono, dtype=np.float32)
    n = len(mono)
    if lowpass_hz:
        lib.one_pole(mono.ctypes.data, n, 1.0 - math.exp(-2.0 * math.pi * lowpass_hz / YM_RATE))
    ratio = YM_RATE / OUT_RATE
    n_out = int(n / ratio)
    out = np.zeros(max(n_out, 1), dtype=np.float32)
    if n_out:
        lib.resample(mono.ctypes.data, n, out.ctypes.data, n_out, ratio, 64,
                     0.95 * 20000.0 / (OUT_RATE / 2.0))
        lib.dc_block(out.ctypes.data, n_out, math.exp(-2.0 * math.pi * DC_HZ / OUT_RATE))
    return out[:n_out]


def to_pcm16(x):
    import numpy as np
    y = np.round(x.astype(np.float64) * GAIN)
    clipped = int(np.count_nonzero((y > 32767) | (y < -32768)))
    y = np.clip(y, -32768, 32767).astype("<i2")
    peak = int(np.abs(y.astype(np.int32)).max()) if len(y) else 0
    return y.tobytes(), clipped, peak


def write_wav(path, pcm, rate, loop=None):
    chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16),
              b"data" + struct.pack("<I", len(pcm)) + pcm + (b"\0" if len(pcm) & 1 else b"")]
    if loop is not None:
        # Godot's importer (loop mode "Detect From WAV") reads dwStart/dwEnd as
        # AudioStreamWAV.loop_begin/loop_end, and loop_end is exclusive there, so dwEnd
        # holds the exclusive end (one past the last sample of the loop).
        start, end = loop
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(round(1e9 / rate)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, start, end, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    body = b"WAVE" + b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def trim_tail(x, thresh=1.5 / GAIN):
    """Drop trailing samples that quantise to (near) silence."""
    import numpy as np
    loud = np.nonzero(np.abs(x) >= thresh)[0]
    return x[:loud[-1] + 1] if len(loud) else x[:0]


def spec_err(x, a, b, length, w=1024):
    """Relative magnitude-spectrum difference of x[a:a+length] vs x[b:b+length]."""
    import numpy as np
    han = np.hanning(w)
    num = den = 0.0
    for i in range(0, length - w + 1, w // 2):
        p = np.abs(np.fft.rfft(x[a + i:a + i + w] * han))
        q = np.abs(np.fft.rfft(x[b + i:b + i + w] * han))
        num += float(((p - q) ** 2).sum())
        den += float((p ** 2).sum())
    return (num / den) ** 0.5 if den else 0.0


def find_loop(x, a0, b0, lo=0.25, hi=3.0, thresh=0.12):
    """Loop points in output samples. Pass 1 plays the loop body from a0 (silence before
    it); pass 2 starts at b0 with pass 1's last notes still ringing. Find the first offset
    d where pass 2 sounds like pass 1 again (magnitude spectra over the next 0.25 s), then
    loop [a0+d, b0+d): playing on from b0+d and jumping back to a0+d are the same music.
    Returns (start, end, spectral error at the seam)."""
    import numpy as np
    span = int(0.25 * OUT_RATE)
    step = int(0.01 * OUT_RATE)
    best = None
    d = int(lo * OUT_RATE)
    while d <= int(hi * OUT_RATE) and b0 + d + span <= len(x):
        e = spec_err(x, a0 + d, b0 + d, span)
        if best is None or e < best[1]:
            best = (d, e)
        if e < thresh:
            break
        d += step
    d, e = best
    # Fine-tune within +-10 ms: the smallest waveform mismatch over the crossfade.
    fine = None
    for dd in range(max(XFADE, d - step), d + step + 1):
        if b0 + dd > len(x):
            break
        diff = x[a0 + dd - XFADE:a0 + dd] - x[b0 + dd - XFADE:b0 + dd]
        m = float(np.abs(diff).sum())
        if fine is None or m < fine[1]:
            fine = (dd, m)
    d = fine[0]
    return a0 + d, b0 + d, e


def seam_crossfade(x, start, end):
    """Blend the XFADE samples before loop_end into those before loop_start, so the jump
    from end-1 back to start continues the waveform it would have reached anyway."""
    import numpy as np
    t = (np.arange(XFADE, dtype=np.float32) + 0.5) / XFADE
    y = x.copy()
    y[end - XFADE:end] = x[end - XFADE:end] * (1 - t) + x[start - XFADE:start] * t
    return y


def dac_summary(rom, info, sid):
    """DAC notes of an effect (the priority rule needs instrument and keyed time). Songs
    get one row per distinct (instrument, note)."""
    rows = []
    seen = set()
    for d in info["dac"]:
        key = (d["instr"], d["note"])
        if sid >= 0x30 and key in seen:
            continue
        seen.add(key)
        step = dac_step(rom, d["note"])
        smp = u32(rom, DAC_TABLE + 8 * (d["instr"] - 0x60))
        ln = 0
        if smp:
            while rom[smp + ln]:
                ln += 1
        row = {"instr": "0x%02X" % d["instr"], "note": d["note"], "step": step,
               "rate_hz": round(dac_rate(step)), "sample_bytes": ln,
               "sample_seconds": round(ln / dac_rate(step), 3) if step else None}
        if sid < 0x30:
            row.update({"velocity": d["velocity"], "on_tick": d["on_tick"],
                        "off_tick": d["off_tick"]})
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------- crowd noise

# The crowd (updatesound L52982, KillCrowd L53013) is the PSG's noise channel: white noise
# ($E7: feedback on, clocked by tone channel 2), tone 2's period $018, its attenuation
# following the crowd meter. The Mega Drive's PSG shifts a 16-bit register tapped at bits
# 0 and 3 (period 57337) on every other tone-2 edge: 3579545 / 16 / $18 / 2 = 4660.9 Hz.
# The level is GPGX's measured PSG/FM balance (psg.c: a channel at full volume swings
# 2800 x 1.5 against the YM's 24-clock sum x 11, "adjusted to match VA4 MD1").
CROWD_SHIFT_MCLK = 15 * 16 * 0x18 * 2
CROWD_LEVEL = 2800 * 1.5 / 11.0


def render_crowd(lib, lowpass_hz):
    """One period of the crowd noise at attenuation 0 (full), DC-free, at OUT_RATE.
    Returns (float32 samples, LFSR period)."""
    import numpy as np
    v = start = 0x8000
    bits = []
    while True:
        fb = bin(v & 9).count("1") & 1
        v = (v >> 1) | (fb << 15)
        bits.append(v & 1)
        if v == start:
            break
    period = len(bits)
    b = np.array(bits * 2, dtype=np.float64)
    cum = np.concatenate([[0.0], np.cumsum(b)])
    n = int(len(b) * CROWD_SHIFT_MCLK // MCLK_PER_YM_SAMPLE)
    t = np.arange(n + 1, dtype=np.float64) * MCLK_PER_YM_SAMPLE
    j = np.minimum((t // CROWD_SHIFT_MCLK).astype(np.int64), len(b) - 1)
    area = cum[j] * CROWD_SHIFT_MCLK + (t - j * CROWD_SHIFT_MCLK) * b[j]
    native = np.diff(area) / MCLK_PER_YM_SAMPLE * CROWD_LEVEL
    out = mono_to_output(lib, native, lowpass_hz)
    one = int(round(period * CROWD_SHIFT_MCLK / MASTER * OUT_RATE))
    x = out[one:2 * one]
    return (x - x.mean()).astype(np.float32), period


# ---------------------------------------------------------------------------- id table

def game_song_ids(rom):
    """ids song() can be asked for: ChooseSong tables plus the fixed call sites."""
    tab = rom[0xFE5B0:0xFE5B0 + 28 * 6]
    fall = rom[0xFE658:0xFE660]
    ids = {b for b in tab if b} | set(fall) | {0x0B, 0x0C, 0x0D, 0x0F, 0x78, 0x79, 0x7A}
    return sorted(ids)


SFX_USES = {
    0x00: "after a goal (checkgoal L49814): siren", 0x01: "ding: breakaway (L39781, L39940), "
    "assnearest L40599; penalty-time tick (updatepentime L46877)",
    0x02: "penalty over (updatepentime L46877); one minute left (L51797)",
    0x03: "whistle (Stop4Pen L46476)", 0x04: "horn, end of period (clockcont L30082)",
    0x05: "shot wiff (doshot); puck contact (checkpuckcoll L50528)",
    0x06: "stick deflection (puckstick L50608)", 0x07: "no call site found",
    0x08: "puck hits the net frame, play live (checkgoal L49726)",
    0x09: "no retail call site (fight patch: punch, high)",
    0x0A: "no retail call site (fight patch: punch, low)",
    0x0B: "crowd cheer: song() from AddPenalty L45970, FallDown L49489, puckstick L50690, "
          "puckgoalie L50879", 0x0C: "crowd boo: song() from AddPenalty, FallDown",
    0x0D: "injury (setInjuryType L49503, sfx); away goalie save (puckgoalie L50879, song)",
    0x0E: "puck over / at the glass (wallcollb2 L50115)",
    0x0F: "crowd bed when home leads after the game (song() L55725)",
    0x10: "pass, loudest: $10 + (($C - puckvz.b) >> 2 & 3) (passmode L37066)",
    0x11: "pass", 0x12: "pass", 0x13: "pass, quietest",
    0x14: "backhand shot, hardest: $14 + max(3 - speed/16, 0) (doshot L37692)",
    0x15: "backhand shot", 0x16: "backhand shot", 0x17: "backhand shot, softest",
    0x18: "forehand shot, hardest", 0x19: "forehand shot",
    0x1A: "forehand shot", 0x1B: "forehand shot, softest",
    0x1C: "body check, ltack 0 (newcheck L48769); goalie frame $2C8 (L39092)",
    0x1D: "body check, ltack 1", 0x1E: "body check, ltack 2", 0x1F: "body check, ltack 3",
    0x20: "player hits the boards (L50205)", 0x21: "no call site (player hits boards variant)",
    0x22: "no call site (player hits boards variant)",
    0x23: "no call site (player hits boards variant)",
    0x24: "puck hits a body / goalie (puckbody L50776, puckgoalie L50882)",
    0x25: "puck hits the net frame, clock stopped (checkgoal L49726)",
    0x26: "empty (points at the end event of $01)", 0x27: "empty (points at the end event of $01)",
    0x28: "puck hits the boards, loudest: $28 + (d0 & 3) (wallcoll L50184)",
    0x29: "puck hits the boards", 0x2A: "puck hits the boards",
    0x2B: "puck hits the boards, quietest",
    0x2C: "puck lands on the ice, loudest (updateplayers L35554)", 0x2D: "puck lands on the ice",
    0x2E: "puck lands on the ice", 0x2F: "puck lands on the ice, quietest; puck drop (Endfaceoff L42447)",
    0x78: "title (newTitleScreen L975422) / game over (L53862)",
    0x79: "period over / intermission (PeriodOver L53840, L48340, PlayoffScreen L54022)",
    0x7A: "after the game setup screens (sub_FCC76 L969620)",
}


# ---------------------------------------------------------------------------- main

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    rom_path = args[0] if args else "lst/nhl94.bin"
    out = args[1] if len(args) > 1 else "godot/assets/audio"
    only = None
    for f in flags:
        if f.startswith("--ids="):
            only = [int(x, 0) for x in f[6:].split(",") if x]
    engine = "gpgx"
    filt = "model1"
    for f in flags:
        if f.startswith("--engine="):
            engine = f[9:]
        if f.startswith("--filter="):
            filt = f[9:]
    assert engine in ("gpgx", "unicorn"), engine
    lowpass = FILTERS[filt]
    verify = "--verify" in flags
    rom = open(rom_path, "rb").read()
    if zlib.crc32(rom) != ROM_CRC:
        sys.exit("ROM CRC32 %08X != %08X" % (zlib.crc32(rom), ROM_CRC))
    for a, hexs in ENTRY_BYTES.items():
        assert rom[a:a + len(hexs) // 2].hex() == hexs, hex(a)
    uc_mod, mk = import_unicorn()
    lib = build_core()
    gx = Gpgx(rom_path) if engine == "gpgx" else None
    os.makedirs(os.path.join(out, "sfx"), exist_ok=True)
    os.makedirs(os.path.join(out, "music"), exist_ok=True)

    song_ids = game_song_ids(rom)
    ids = list(range(0x7B)) if only is None else only
    meta_path = os.path.join(out, "audio.json")
    meta = {}
    if only is not None and os.path.exists(meta_path):
        meta = json.load(open(meta_path))
    entries = meta.get("ids", {})
    for sid in ids:
        info = scan_sequence(rom, sid)
        key = "0x%02X" % sid
        is_music = sid >= 0x30
        # Frame cap: the static tick length plus slack (loops render a second pass).
        cap = info["ticks"] + 60 + (info["ticks"] if info["end"] == "loop" else 0) + 300
        r = render(lib, rom, uc_mod, mk, sid, cap, log_writes=verify)
        if gx:
            # The same id from the same frame of a game in progress; the unicorn render
            # still supplies the sequence events, loop frames and length. Effects get
            # half a second more for the (slightly slower) DAC.
            more = 0 if r["loop_frames"] else 30
            r["native"], r["n"], r["frame_samples"] = gx.render(sid, r["frames"] + more)
        fs = r["frame_samples"]
        ratio = YM_RATE / OUT_RATE
        loop = None
        loop_err = None
        x, stereo = to_output(lib, r["native"], r["n"], lowpass)
        if r["loop_frames"]:
            jf = r["loop_frames"][0]
            tgt = r["jumps"][0][2]
            starts = [ev[0] for ev in r["events"] if ev[2] == tgt]
            lsf = starts[0] if starts else 0
            a0 = int(round(fs[lsf] / ratio))
            b0 = int(round(fs[jf] / ratio))
            la, lb, loop_err = find_loop(x, a0, b0)
            x = seam_crossfade(x, la, lb)[:lb]
            loop = (la, lb)
        else:
            x = trim_tail(x)
        pcm, clipped, peak = to_pcm16(x)
        names = []
        if sid < 0x30:
            names.append(("sfx", "sfx_%02x.wav" % sid))
        if is_music or sid in (0x0B, 0x0C, 0x0D, 0x0F):
            names.append(("music", "song_%02x.wav" % sid))
        empty = info["notes"] == 0
        files = []
        for d, nm in names:
            if empty:
                continue
            write_wav(os.path.join(out, d, nm), pcm, OUT_RATE, (la, lb) if loop else None)
            files.append("%s/%s" % (d, nm))
        voice_kinds = sorted({"fm" if i < 0x60 else "dac"
                              for i in info["fm_instruments"] + info["dac_instruments"]})
        e = {
            "files": files,
            "kind": "music" if is_music else "sfx",
            "use": SFX_USES.get(sid, "organ tune (ChooseSong)" if 0x30 <= sid < 0x78 else ""),
            "game_uses_song": sid in song_ids,
            "seq_addr": "0x%05X" % info["start"],
            "seq_ticks": info["ticks"],
            "seq_end": info["end"],
            "notes": info["notes"],
            "channels": info["channels"],
            "fm_instruments": ["0x%02X" % i for i in info["fm_instruments"]],
            "dac_instruments": ["0x%02X" % i for i in info["dac_instruments"]],
            "voices": voice_kinds,
            "fm_max_voices": info["fm_max_voices"],
            "dac_notes": dac_summary(rom, info, sid),
            "stops_music": sid >= 0x30,
            "slot_seconds": round(info["ticks"] / FRAME_HZ, 3),
            "dac_priority": ("0x%02X" % max(d["instr"] for d in info["dac"])
                             if info["dac"] and sid < 0x30 else None),
            "dac_busy_seconds": (round(max((d["off_tick"] if d["off_tick"] is not None
                                            else info["ticks"]) for d in info["dac"])
                                       / FRAME_HZ, 3) if info["dac"] and sid < 0x30 else None),
            "samples": len(x),
            "duration": round(len(x) / OUT_RATE, 4),
            "frames_rendered": r["frames"],
            "context": Gpgx.context(sid) if gx else None,
            "loops": bool(loop),
            "loop_start": la if loop else None,
            "loop_end": lb if loop else None,
            "loop_seam_rel_error": round(loop_err, 4) if loop else None,
            "peak": peak,
            "clipped": clipped,
            "stereo": stereo,
        }
        if verify:
            e["verify"] = {"psg_writes": r["psg_writes"], "ym_writes_by_68k": r["ym68k"],
                           "z80_fm_writes": len(r.get("ymlog", []))}
        entries[key] = e
        print("%s %-6s %6.2fs %s%s peak=%d%s" % (key, e["kind"], e["duration"],
              "loop %d-%d err %.3f " % (la, lb, loop_err) if loop else "",
              ",".join(voice_kinds) or "empty", peak, " CLIP %d" % clipped if clipped else ""))
        sys.stdout.flush()
    crowd = meta.get("crowd_noise")
    if only is None or "--crowd" in flags:
        x, period = render_crowd(lib, lowpass)
        pcm, clipped, peak = to_pcm16(x)
        write_wav(os.path.join(out, "crowd_noise.wav"), pcm, OUT_RATE, (0, len(x)))
        crowd = {"file": "crowd_noise.wav", "samples": len(x), "loops": True,
                 "attenuation": 0, "attenuation_step_db": 2.0, "lfsr_period": period,
                 "shift_hz": round(MASTER / CROWD_SHIFT_MCLK, 2), "peak": peak,
                 "notes": "PSG noise at full volume (attenuation 0). updatesound sets "
                          "attenuation 15 - (asv >> 8); play at -2 dB a step, silent at 15."}
        print("crowd noise %.2fs peak=%d" % (len(x) / OUT_RATE, peak))
    meta = {
        "crowd_noise": crowd,
        "format": {"rate": OUT_RATE, "bits": 16, "channels": 1, "gain": GAIN,
                   "dc_block_hz": DC_HZ, "native_rate": round(YM_RATE, 3),
                   "frame_hz": round(FRAME_HZ, 4), "engine": engine,
                   "engine_detail": ("Genesis Plus GX %s, Nuked YM2612, inside a game in "
                                     "progress" % GPGX_COMMIT[:10] if gx else
                                     "unicorn 68000 + Z80 core, bank_wait_cycles %d"
                                     % BANK_WAIT),
                   "filter": filt, "lowpass_hz": lowpass},
        "notes": "Rendered by tools/extract/audio.py from the retail driver (docs/specs/audio.md). "
                 "loop_start/loop_end are sample frames (end exclusive) at 'rate'.",
        "mixing": {
            "fm_voices": 5, "dac_voices": 1,
            "rules": "See docs/specs/audio.md section 6: ids >= $30 stop the current music; "
                     "8 sequence slots (a request with no free slot is dropped); FM notes take "
                     "the free or oldest of 5 FM voices; every DAC instrument shares the one DAC "
                     "voice and a new DAC note only replaces a sounding one with a higher "
                     "instrument number.",
        },
        "song_ids_used": ["0x%02X" % i for i in song_ids],
        "choose_song": {
            "table": "unk_FE5B0 (6 bytes per HmTeam, index SongIndex 0..5; 0 = random)",
            "random": "unk_FE658[randomd0(8) & 7]",
            "per_team": {str(t): ["0x%02X" % b for b in rom[0xFE5B0 + 6 * t:0xFE5B6 + 6 * t]]
                         for t in range(28)},
            "fallback": ["0x%02X" % b for b in rom[0xFE658:0xFE660]],
        },
        "ids": dict(sorted(entries.items())),
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
