#!/usr/bin/env python3
"""Synthesize a whistled melody as a 16-bit mono WAV — no deps (stdlib only).

Timbre matched to Reachy's own whistle (measured from the emotions-library
`dance2` clip): a near-pure sine (2nd harmonic ~0.066, 3rd ~0.019, higher
negligible), NO breathiness, and ~1.5% vibrato at 5.5 Hz. The key to not
sounding "MIDI" is legato: one continuous phase for the whole tune with a
short pitch GLIDE (portamento) between notes and a soft tongued dip at note
onsets instead of silence — real whistlers slur, they don't retrigger.

Usage: whistle-synth.py <tune> <out.wav>
       whistle-synth.py list
"""
import sys, math, wave, struct, random

SR = 22050
# Harmonic stack sets the timbre. A near-pure sine ([1, .066, .019]) is a
# clean whistle; a fuller stack adds the voiced "mmm" throat-hum buzz. This
# is a moderate hum — warm and voiced but still robotic once low-passed.
HARMONICS = [1.0, 0.32, 0.18, 0.10, 0.05]
HNORM = sum(HARMONICS)         # keep peak in range as harmonics are added
VIB_RATE, VIB_DEPTH = 5.5, 0.004   # very subtle — robot-steady pitch, not a wail
VIB_ONSET = 0.28               # secs into a note before vibrato reaches full
GLIDE_S = 0.006                # tiny anti-zipper glide only (no smear/ghost)
ART_DEPTH = 0.45               # how deep the articulation notch dips at onsets
ART_W = 0.016                  # half-width (s) of the smooth onset notch
BREATH = 0.0                   # no air hiss — it read as ghost-wind; keep it clean
LPF_HZ = 2200                  # gentle low-pass to smoothen tone edges / warm it

# --- Melodies: (midi_note, beats); note 0 = rest. C4=60, A4=69. ---
TUNES = {
    # Darth Vader's theme (G minor)
    "imperial-march": (108, [
        (67,1),(67,1),(67,1),(63,0.75),(70,0.25),(67,1),(63,0.75),(70,0.25),(67,2),
        (74,1),(74,1),(74,1),(75,0.75),(70,0.25),(66,1),(63,0.75),(70,0.25),(67,2),
    ]),
    # Main Title fanfare (C major)
    "star-wars-theme": (120, [
        (67,0.5),(67,0.5),(67,0.5),
        (72,3),(79,3),
        (77,0.5),(76,0.5),(74,0.5),(84,3),(79,1),
        (77,0.5),(76,0.5),(74,0.5),(84,3),(79,1),
        (77,0.5),(76,0.5),(77,0.5),(74,3),
    ]),
    # The Force Theme / Binary Sunset (opening phrase, C major)
    "force-theme": (100, [
        (67,1),(72,2),(71,0.5),(72,0.5),(76,2),(72,1),
        (76,0.5),(75,0.5),(76,0.5),(79,2.5),(0,0.5),
        (74,1),(77,2),(76,0.5),(77,0.5),(81,2),
    ]),
    # Cantina Band "Mad About Me" (simplified riff, swung feel flattened)
    "cantina-band": (150, [
        (69,0.5),(76,0.5),(69,0.5),(76,0.5),
        (69,0.5),(76,0.5),(77,0.5),(76,0.5),(74,1),(0,0.5),
        (69,0.5),(76,0.5),(69,0.5),(76,0.5),
        (69,0.5),(74,0.5),(72,0.5),(71,0.5),(69,1),
    ]),
}

def midi_to_freq(m):
    return 440.0 * (2.0 ** ((m - 69) / 12.0))

def render_tune(name):
    """Continuous-phase, legato synthesis: build per-sample freq + amp
    envelopes for the whole melody (gliding between notes, dipping instead
    of silencing at onsets), then integrate one phase through it all."""
    bpm, notes = TUNES[name]
    spb = 60.0 / bpm
    glide = int(GLIDE_S * SR)

    freqs, amps, vibs = [], [], []
    onsets = []                       # sample indices where a sung note begins
    prev_f = None
    von = max(1, int(VIB_ONSET * SR))
    for midi, beats in notes:
        n = int(SR * beats * spb)
        if n <= 0:
            continue
        rest = (midi == 0)
        f = prev_f if (rest and prev_f) else (midi_to_freq(midi) if not rest else 440.0)
        g = glide if (prev_f is not None and not rest) else 0
        if not rest and prev_f is not None:
            onsets.append(len(freqs))  # mark this onset for an articulation notch
        for i in range(n):
            fr = prev_f + (f - prev_f) * (i / g) if (g and i < g) else f
            freqs.append(fr)
            vibs.append(0.0 if rest else min(1.0, i / von))
            amps.append(0.0 if rest else 1.0)   # flat sustain; notches added below
        if not rest:
            prev_f = f

    # Smooth articulation notches at each onset (continuous -> no clicks/"beats")
    w = max(2, int(ART_W * SR))
    for o in onsets:
        for k in range(-w, w + 1):
            j = o + k
            if 0 <= j < len(amps):
                dip = ART_DEPTH * 0.5 * (1.0 + math.cos(math.pi * k / w))  # peak at onset
                amps[j] *= (1.0 - dip)

    # global fade in/out
    fi, fo = int(0.02 * SR), int(0.06 * SR)
    for i in range(min(fi, len(amps))):
        amps[i] *= i / fi
    for i in range(min(fo, len(amps))):
        amps[-1 - i] *= i / fo

    out, phase, prev_raw = [], 0.0, 0.0
    for i, fr in enumerate(freqs):
        t = i / SR
        vf = fr * (1.0 + VIB_DEPTH * vibs[i] * math.sin(2 * math.pi * VIB_RATE * t))
        phase += 2 * math.pi * vf / SR
        tone = sum(h * math.sin((k + 1) * phase) for k, h in enumerate(HARMONICS)) / HNORM
        raw = random.random() - 0.5
        air = raw - prev_raw          # high-pass -> breath/air hiss, not rumble
        prev_raw = raw
        out.append((tone + BREATH * air) * amps[i] * 0.30)

    # gentle one-pole low-pass to smoothen tone edges / any residual grain
    a = (2 * math.pi * LPF_HZ / SR) / (1 + 2 * math.pi * LPF_HZ / SR)
    y = 0.0
    for i in range(len(out)):
        y += a * (out[i] - y)
        out[i] = y
    return out

def write_wav(path, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-1.0, min(1.0, s)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))

if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "list":
        print(" ".join(sorted(TUNES))); sys.exit(0)
    if len(sys.argv) != 3 or sys.argv[1] not in TUNES:
        sys.stderr.write("usage: whistle-synth.py <%s> <out.wav>\n" % "|".join(sorted(TUNES)))
        sys.exit(2)
    write_wav(sys.argv[2], render_tune(sys.argv[1]))
