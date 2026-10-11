#!/usr/bin/env python3
"""Export the 28 NHL '94 team records to Godot TeamData resources.

Offline only. The game never reads the ROM; it loads godot/data/teams/*.tres.
Usage: python3 tools/extract/teams.py [lst/nhl94.bin] [godot/data/teams]

Source: the team pointer table at ROM $30E (28 longs) and the records it points to.
Layout and decoding: docs/specs/data_attributes.md sections 1.1-1.6. src/teamdata94.asm
is the NHL '93 data and is not used.

Ratings are written as the retail roster-screen values (25-99, hot/cold 0) so the
resources read like the game's own screens. PlayerData turns them back into the 0-15
nibbles setplayer reads; every ROM nibble round-trips exactly (checked below).
"""
import os
import sys

TEAM_TABLE = 0x30E
TEAMS = 28

# 1993-94 alignment (Eastern: Atlantic, Northeast; Western: Central, Pacific).
DIVISION = {
    "FLA": "ATLANTIC", "NJ": "ATLANTIC", "NYI": "ATLANTIC", "NYR": "ATLANTIC",
    "PHI": "ATLANTIC", "TB": "ATLANTIC", "WSH": "ATLANTIC",
    "BOS": "NORTHEAST", "BUF": "NORTHEAST", "HFD": "NORTHEAST", "MTL": "NORTHEAST",
    "OTW": "NORTHEAST", "PIT": "NORTHEAST", "QUE": "NORTHEAST",
    "CHI": "CENTRAL", "DAL": "CENTRAL", "DET": "CENTRAL", "STL": "CENTRAL",
    "TOR": "CENTRAL", "WPG": "CENTRAL",
    "ANH": "PACIFIC", "CGY": "PACIFIC", "EDM": "PACIFIC", "LA": "PACIFIC",
    "SJ": "PACIFIC", "VAN": "PACIFIC",
}
DIVISIONS = ["ATLANTIC", "NORTHEAST", "CENTRAL", "PACIFIC", "NONE"]
CONFERENCES = ["EASTERN", "WESTERN", "ALL_STAR"]


def display(n: int) -> int:
    """Roster-screen value of a nibble with hot/cold 0 (CalcAttrib + AttribAdjust)."""
    v = 18 * n
    if v >= 100:
        return 99
    if v < 50:
        return (v >> 1) + 25
    return v


def fight_display(n: int) -> int:
    """The fight patch's Fgt column (fgtdisp, NHLPA '93 style): (H/F & $E) * 100 / 14,
    no curve. Retail never shows fighting. Fight nibbles reach 7 in the patched rosters."""
    return (2 * n * 100) // 14


def fight_nibble_of(r: float) -> int:
    """PlayerData.fight_nibble_of: the 0-7 nibble whose Fgt value is nearest."""
    return min(range(8), key=lambda n: (abs(fight_display(n) - r), n))


def nibble_of(r: float) -> int:
    """PlayerData.nibble_of: the nibble whose display value is nearest (ties go low)."""
    best, best_d = 0, None
    for n in range(7):
        d = abs(display(n) - r)
        if best_d is None or d < best_d:
            best, best_d = n, d
    return best


class Rom:
    def __init__(self, data: bytes):
        self.b = data

    def w(self, a: int) -> int:
        return (self.b[a] << 8) | self.b[a + 1]

    def l(self, a: int) -> int:
        return (self.w(a) << 16) | self.w(a + 2)

    def pstr(self, a: int):
        n = self.w(a)
        s = self.b[a + 2:a + n].rstrip(b"\x00").decode("latin-1")
        return s, a + n


def read_team(rom: Rom, t: int) -> dict:
    T = rom.l(TEAM_TABLE + 4 * t)
    off = [rom.w(T + 2 * i) for i in range(6)]
    R = T + off[4]
    team = {
        "index": t,
        "sim_offense": (rom.b[R] >> 4) & 7,
        "sim_defense": rom.b[R] & 7,
        "pp_bonus": rom.b[R + 1] & 15,
        "pk_penalty": rom.b[R + 1] >> 4,
        "home_bonus": rom.b[R + 2] >> 4,
        "away_penalty": rom.b[R + 2] & 15,
        "forwards": rom.b[R + 3] >> 4,
        "defense": rom.b[R + 3] & 15,
    }
    gw = rom.w(T + off[5])
    team["goalie_word"] = gw
    g = 0
    while True:
        g += 1
        gw = (gw << 4) & 0xFFFF
        if gw == 0:
            break
    team["goalies"] = g
    team["pal_home"] = [rom.w(T + off[1] + 2 * i) for i in range(16)]
    team["pal_away"] = [rom.w(T + off[1] + 32 + 2 * i) for i in range(16)]
    team["lines"] = [rom.b[T + off[3] + i] for i in range(64)]
    a = T + off[2]
    team["city"], a = rom.pstr(a)
    team["abbr"], a = rom.pstr(a)
    team["nickname"], a = rom.pstr(a)
    team["arena"], a = rom.pstr(a)
    players = []
    a = T + off[0]
    while rom.w(a) != 2:
        name, b = rom.pstr(a)
        players.append({"name": name, "attr": list(rom.b[b:b + 8])})
        a = b + 8
    team["players"] = players
    assert len(players) == g + team["forwards"] + team["defense"], team["abbr"]
    return team


def player_fields(p: dict, role: str) -> list:
    A = p["attr"]
    hi = lambda x: x >> 4
    lo = lambda x: x & 15
    jersey = 10 * hi(A[0]) + lo(A[0])
    hand = "RIGHT" if A[4] & 1 else "LEFT"
    fields = [
        ("full_name", '"%s"' % p["name"].replace('"', '\\"')),
        ("jersey_number", str(jersey)),
        ("position", {"F": "0", "D": "1", "G": "2"}[role]),
        ("handedness", "1" if hand == "RIGHT" else "0"),
        ("weight_lbs", "%d.0" % (140 + 8 * hi(A[1]))),
        ("agility", "%d.0" % display(lo(A[1]))),
        ("speed", "%d.0" % display(hi(A[2]))),
        ("offensive_awareness", "%d.0" % display(lo(A[2]))),
        ("defensive_awareness", "%d.0" % display(hi(A[3]))),
    ]
    if role == "G":
        fields += [
            ("puck_control", "%d.0" % display(lo(A[3]))),
            ("stick_right", "%d.0" % display(hi(A[6]))),
            ("stick_left", "%d.0" % display(lo(A[6]))),
            ("glove_right", "%d.0" % display(hi(A[7]))),
            ("glove_left", "%d.0" % display(lo(A[7]))),
        ]
        # Nibbles that are 0 in every goalie record still round-trip through the
        # skater fields (left at their 25 default = nibble 0).
        fields += [
            ("checking", "%d.0" % display(hi(A[4]))),
            ("fighting", "%d.0" % fight_display((lo(A[4]) >> 1) & 7)),
            ("stick_handling", "%d.0" % display(hi(A[5]))),
            ("shot_accuracy", "%d.0" % display(lo(A[5]))),
        ]
    else:
        fields += [
            ("shot_power", "%d.0" % display(lo(A[3]))),
            ("checking", "%d.0" % display(hi(A[4]))),
            ("fighting", "%d.0" % fight_display((lo(A[4]) >> 1) & 7)),
            ("stick_handling", "%d.0" % display(hi(A[5]))),
            ("shot_accuracy", "%d.0" % display(lo(A[5]))),
            ("endurance", "%d.0" % display(hi(A[6]))),
            ("shot_bias", "%d.0" % display(lo(A[6]))),
            ("pass_accuracy", "%d.0" % display(hi(A[7]))),
            ("aggressiveness", "%d.0" % display(lo(A[7]))),
        ]
    return fields


def check_round_trip(p: dict, role: str) -> None:
    """The nibbles PlayerData will rebuild equal the ROM nibbles (0-6 range)."""
    A = p["attr"]
    nibs = [A[1] & 15, A[2] >> 4, A[2] & 15, A[3] >> 4, A[3] & 15, A[4] >> 4,
            A[5] >> 4, A[5] & 15, A[6] >> 4, A[6] & 15, A[7] >> 4, A[7] & 15]
    for n in nibs:
        assert 0 <= n <= 6 and nibble_of(display(n)) == n, (p["name"], n)
    f = (A[4] >> 1) & 7
    assert fight_nibble_of(fight_display(f)) == f, (p["name"], f)
    assert (A[4] >> 4) <= 6


def write_tres(team: dict, out_dir: str) -> str:
    abbr = team["abbr"]
    g, f = team["goalies"], team["forwards"]
    subs = []
    refs = []
    for s, p in enumerate(team["players"]):
        role = "G" if s < g else ("F" if s < g + f else "D")
        check_round_trip(p, role)
        sid = "p%d" % s
        refs.append('SubResource("%s")' % sid)
        body = "\n".join("%s = %s" % kv for kv in player_fields(p, role))
        subs.append('[sub_resource type="Resource" id="%s"]\nscript = ExtResource("2")\n%s\n' % (sid, body))
    div = DIVISION.get(abbr, "NONE")
    conf = "ALL_STAR" if div == "NONE" else ("EASTERN" if div in ("ATLANTIC", "NORTHEAST") else "WESTERN")
    nickname = team["nickname"]
    if nickname == "":
        nickname = "All-Stars"
    lines = [
        '[gd_resource type="Resource" script_class="TeamData" load_steps=%d format=3]' % (len(subs) + 3),
        "",
        '[ext_resource type="Script" path="res://data/team_data.gd" id="1"]',
        '[ext_resource type="Script" path="res://data/player_data.gd" id="2"]',
        "",
    ]
    lines += subs
    lines += [
        "[resource]",
        'script = ExtResource("1")',
        "team_index = %d" % team["index"],
        'city = "%s"' % team["city"],
        'team_name = "%s"' % nickname,
        'abbreviation = "%s"' % abbr,
        "conference = %d" % CONFERENCES.index(conf),
        "division = %d" % DIVISIONS.index(div),
        'arena_name = "%s"' % team["arena"],
        'players = Array[ExtResource("2")]([%s])' % ", ".join(refs),
        "goalie_count = %d" % g,
        "forward_count = %d" % f,
        "defense_count = %d" % team["defense"],
        "goalie_marks = %d" % team["goalie_word"],
        "lines = PackedInt32Array(%s)" % ", ".join(str(x) for x in team["lines"]),
        "sim_offense = %d" % team["sim_offense"],
        "sim_defense = %d" % team["sim_defense"],
        "pp_bonus = %d" % team["pp_bonus"],
        "pk_penalty = %d" % team["pk_penalty"],
        "home_bonus = %d" % team["home_bonus"],
        "away_penalty = %d" % team["away_penalty"],
        "home_palette = PackedInt32Array(%s)" % ", ".join(str(x) for x in team["pal_home"]),
        "away_palette = PackedInt32Array(%s)" % ", ".join(str(x) for x in team["pal_away"]),
        "",
    ]
    path = os.path.join(out_dir, "%02d_%s.tres" % (team["index"], abbr.lower()))
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    return path


def main() -> None:
    rom_path = sys.argv[1] if len(sys.argv) > 1 else "lst/nhl94.bin"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "godot/data/teams"
    with open(rom_path, "rb") as fh:
        rom = Rom(fh.read())
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for t in range(TEAMS):
        team = read_team(rom, t)
        write_tres(team, out_dir)
        total += len(team["players"])
    assert total == 684, total
    print(f"wrote {TEAMS} teams, {total} players to {out_dir}")


if __name__ == "__main__":
    main()
