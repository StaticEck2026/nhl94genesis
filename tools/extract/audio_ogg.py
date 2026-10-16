#!/usr/bin/env python3
"""Converts the rendered music (godot/assets/audio/music/song_XX.wav, from audio.py) to
Ogg Vorbis, which keeps the repository small (about 148 MB of WAV). A looping song is cut
at its loop end (audio.json loop_end, exclusive), so the stream's end is the loop end and
SfxBank sets loop_offset = loop_start / rate. Effects stay WAV (short, and the DAC timing
matters). The crowd ids below $30 that audio.py copies into music/ are dropped: the port
plays them from sfx/.

    python3 tools/extract/audio_ogg.py [audio dir] [--keep-wav]

Needs ffmpeg with libvorbis.
"""
import json
import os
import subprocess
import sys


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    keep = "--keep-wav" in sys.argv
    root = args[0] if args else os.path.join(os.path.dirname(__file__), "../../godot/assets/audio")
    meta = json.load(open(os.path.join(root, "audio.json")))
    rate = meta["format"]["rate"]
    music = os.path.join(root, "music")
    for name in sorted(os.listdir(music)):
        if not name.endswith(".wav"):
            continue
        sid = int(name[5:7], 16)
        wav = os.path.join(music, name)
        if sid < 0x30:
            if not keep:
                os.remove(wav)
            continue
        ogg = wav[:-4] + ".ogg"
        entry = meta["ids"]["0x%02X" % sid]
        cmd = ["ffmpeg", "-loglevel", "error", "-y", "-i", wav]
        if entry.get("loops"):
            cmd += ["-af", "atrim=end_sample=%d" % entry["loop_end"]]
        # Fixed serial and no encoder tag: the same input gives the same file.
        cmd += ["-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1",
                "-fflags", "+bitexact", "-flags:a", "+bitexact", "-serial_offset", "0", ogg]
        subprocess.run(cmd, check=True)
        if not keep:
            os.remove(wav)
        print(name, "->", os.path.basename(ogg), "%d KB" % (os.path.getsize(ogg) // 1024))
    _ = rate


if __name__ == "__main__":
    main()
