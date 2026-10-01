#!/usr/bin/env python3
"""Synthesizes the game's placeholder sound effects, and checks them by numbers.

    python3 tools/make_sfx.py                    # write assets/audio/sfx/*.wav, print the check table
    python3 tools/make_sfx.py --only chips win_pot
    python3 tools/make_sfx.py --preview /tmp/sfx_png   # also a waveform + spectrogram PNG per sound
    python3 tools/make_sfx.py --music            # also the lounge loop (slower: ~30s)
    python3 tools/make_sfx.py --check            # only measure the WAVs already on disk

Why a script and not a folder of downloaded sounds: every placeholder is
reproducible from this file, has no licence to track, and can be retuned by
editing a number. Python's standard library only (wave, struct, math, random,
zlib): numpy isn't installed in the cloud sandboxes this was written in, and
a game repo shouldn't need a science stack to rebuild its bleeps.

The style is "retro but warm": sfxr/ChipTone-like building blocks (sine,
triangle, band-limited square and saw, filtered noise, pitch sweeps), but
with soft attacks, upper partials that die faster than the fundamental, and
lowpass filtering on anything buzzy, so a sound repeated a hundred times in
a session never turns harsh. Every sound is 16-bit mono 44.1 kHz (the music
loop is 22.05 kHz to keep the repo small), DC-blocked, peak-normalized to its
own target (UI ticks quiet, the win chime loud) and faded in and out over a
few milliseconds so nothing clicks at the edges.

Each sound seeds its own random generator from its name (crc32), so
regenerating one sound never changes another, and the output is the same on
every run of the same Python (a different libm could, in principle, flip the
lowest bit of a sample here and there).

It was written without being able to listen: --check measures what can be
measured (length, peak, clipping, DC offset, silence at both ends, where the
energy sits in the spectrum) and --preview draws each sound, so a chime can
be seen to have clean partials and a chip to be a short bright transient.
Trust your ears over these when you have them.
"""

import argparse
import math
import os
import random
import struct
import sys
import wave
import zlib

SR = 44100
TAU = 2.0 * math.pi
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")


# ---------------------------------------------------------------- building blocks

def ns(sec, sr=SR):
    return max(1, int(round(sec * sr)))


def zeros(sec, sr=SR):
    return [0.0] * ns(sec, sr)


def _freq_fn(freq):
    return freq if callable(freq) else (lambda _t: freq)


def osc(freq, dur, shape="sine", harmonics=8, phase=0.0, sr=SR):
    """One oscillator. `freq` is Hz or a function of time (for sweeps and
    vibrato); the phase is accumulated so sweeps stay smooth. Square and saw
    are additive (band-limited, `harmonics` partials at most and never past
    Nyquist) instead of naive, which is what keeps them from buzzing."""
    f = _freq_fn(freq)
    n = ns(dur, sr)
    out = [0.0] * n
    ph = phase
    nyq = sr / 2.0
    for i in range(n):
        hz = f(i / sr)
        if shape == "sine":
            v = math.sin(ph)
        elif shape == "tri":
            # Triangle from its odd harmonics (1/k^2, alternating): soft and round.
            v = 0.0
            k = 1
            sign = 1.0
            while k <= 2 * harmonics and k * hz < nyq:
                v += sign * math.sin(k * ph) / (k * k)
                sign = -sign
                k += 2
            v *= 8.0 / (math.pi ** 2)
        elif shape == "square":
            v = 0.0
            k = 1
            while k <= 2 * harmonics and k * hz < nyq:
                v += math.sin(k * ph) / k
                k += 2
            v *= 4.0 / math.pi
        elif shape == "saw":
            v = 0.0
            k = 1
            while k <= harmonics and k * hz < nyq:
                v += math.sin(k * ph) / k
                k += 1
            v *= 2.0 / math.pi
        else:
            raise ValueError(shape)
        out[i] = v
        ph += TAU * hz / sr
    return out


def partials(f0, ratios, amps, taus, dur, sr=SR, attack=0.001):
    """A struck object: sine partials at f0*ratio, each decaying on its own
    time constant. Higher partials get shorter `taus`, the way a real bell
    or chip loses its brightness first."""
    n = ns(dur, sr)
    out = [0.0] * n
    a_n = max(1, int(attack * sr))
    for r, a, tau in zip(ratios, amps, taus):
        hz = f0 * r
        if hz >= sr / 2:
            continue
        w = TAU * hz / sr
        k = math.exp(-1.0 / (tau * sr))
        g = a
        for i in range(n):
            out[i] += g * math.sin(w * i)
            g *= k
    for i in range(min(a_n, n)):
        out[i] *= i / a_n
    return out


def noise(dur, rng, sr=SR):
    return [rng.uniform(-1.0, 1.0) for _ in range(ns(dur, sr))]


def lowpass(x, cutoff, sr=SR):
    """One-pole lowpass; `cutoff` may be a function of time."""
    f = _freq_fn(cutoff)
    out = [0.0] * len(x)
    y = 0.0
    for i, v in enumerate(x):
        a = 1.0 - math.exp(-TAU * f(i / sr) / sr)
        y += a * (v - y)
        out[i] = y
    return out


def highpass(x, cutoff, sr=SR):
    lo = lowpass(x, cutoff, sr)
    return [a - b for a, b in zip(x, lo)]


def bandpass(x, center, q=1.0, sr=SR, block=16):
    """RBJ biquad bandpass (0 dB peak). `center` may be a function of time;
    coefficients are recomputed every `block` samples, plenty for sweeps."""
    f = _freq_fn(center)
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    b0 = b2 = a1 = a2 = 0.0
    for i, v in enumerate(x):
        if i % block == 0:
            hz = min(max(f(i / sr), 20.0), sr * 0.45)
            w0 = TAU * hz / sr
            alpha = math.sin(w0) / (2.0 * q)
            a0 = 1.0 + alpha
            b0 = alpha / a0
            b2 = -alpha / a0
            a1 = -2.0 * math.cos(w0) / a0
            a2 = (1.0 - alpha) / a0
        y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, y
        out[i] = y
    return out


def env(x, attack, decay_tau, hold=0.0, sr=SR):
    """Fast linear attack, optional hold, exponential decay."""
    a_n = max(1, int(attack * sr))
    h_n = int(hold * sr)
    k = math.exp(-1.0 / (decay_tau * sr))
    out = list(x)
    g = 1.0
    for i in range(len(out)):
        if i < a_n:
            out[i] *= i / a_n
        elif i < a_n + h_n:
            pass
        else:
            g *= k
            out[i] *= g
    return out


def adsr(x, a, d, s, r, sr=SR):
    """Attack/decay/sustain/release, release at the end of the buffer."""
    n = len(x)
    a_n, d_n, r_n = int(a * sr), int(d * sr), int(r * sr)
    out = list(x)
    for i in range(n):
        if i < a_n:
            g = i / a_n
        elif i < a_n + d_n:
            g = 1.0 - (1.0 - s) * (i - a_n) / max(1, d_n)
        else:
            g = s
        if i >= n - r_n:
            g *= (n - i) / max(1, r_n)
        out[i] *= g
    return out


def shape_by(x, fn, sr=SR):
    """Multiply by an arbitrary gain curve fn(t)."""
    return [v * fn(i / sr) for i, v in enumerate(x)]


def gain(x, g):
    return [v * g for v in x]


def mix(dur, *parts, sr=SR):
    """parts: (signal, start_seconds, gain). Anything past `dur` is dropped."""
    out = [0.0] * ns(dur, sr)
    for sig, start, g in parts:
        o = int(start * sr)
        for i, v in enumerate(sig):
            j = o + i
            if j >= len(out):
                break
            if j >= 0:
                out[j] += v * g
    return out


def soft_clip(x, drive=1.0):
    t = math.tanh(drive)
    return [math.tanh(v * drive) / t for v in x]


def note(name):
    """'A4' -> Hz. Sharps only (C#5), which is all the cues below need."""
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names.index(pitch) + 12 * (octave + 1) - 69) / 12.0)


def finish(x, peak_db, fade_in=0.003, fade_out=0.02, sr=SR):
    """DC-block (a 20 Hz highpass, not just subtracting the mean, so a
    decaying offset doesn't thump), raised-cosine fades at both ends, then
    peak-normalize to `peak_db` dBFS."""
    x = highpass(x, 20.0, sr)
    n = len(x)
    fi, fo = max(1, int(fade_in * sr)), max(1, int(fade_out * sr))
    for i in range(min(fi, n)):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fi)
    for i in range(min(fo, n)):
        x[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fo)
    m = max(abs(v) for v in x) or 1.0
    g = 10 ** (peak_db / 20.0) / m
    return [v * g for v in x]


def write_wav(path, x, sr=SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = struct.pack("<%dh" % len(x), *(max(-32767, min(32767, int(round(v * 32767)))) for v in x))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)


def read_wav(path):
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        raw = w.readframes(w.getnframes())
        assert w.getsampwidth() == 2 and w.getnchannels() == 1, path
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return [v / 32768.0 for v in vals], sr


# ---------------------------------------------------------------- the sounds
# Each function takes its own seeded rng and returns (samples, peak_db).
# Peak targets set the mix: UI ticks and rustles quiet (-9 to -12 dB), table
# sounds in the middle, the big moments (win, all-in, fine) near -2 dB. The
# voices were first all normalized near -6 dB peak and measured from -13.6
# dB RMS (the owl, a sustained tone) to -30 dB RMS (the squirrel, sparse
# clicks), so their peaks were spread out to bring them within ~8 dB RMS of
# each other.

def clink(rng, f0=None, bright=1.0, dur=0.09):
    """One clay chip striking another: a click plus a few inharmonic partials
    in the 3-9 kHz range that are gone within ~30 ms."""
    f0 = f0 or rng.uniform(2700, 3600)
    ratios = [1.0, 1.52 + rng.uniform(-0.04, 0.04), 2.26 + rng.uniform(-0.05, 0.05), 2.93]
    amps = [1.0, 0.65, 0.4 * bright, 0.22 * bright]
    taus = [0.028, 0.018, 0.011, 0.007]
    body = partials(f0, ratios, amps, taus, dur)
    click = env(highpass(noise(0.006, rng), 3000), 0.0003, 0.0015)
    return mix(dur, (body, 0, 0.8), (click, 0, 0.5))


def thump(rng, f_start=150, f_end=70, dur=0.12, tau=0.035):
    """A soft low knock: a sine dropping in pitch plus a little lowpassed noise."""
    body = env(osc(lambda t: f_end + (f_start - f_end) * math.exp(-t / 0.02), dur), 0.001, tau)
    grit = env(lowpass(noise(dur, rng), 900), 0.0005, tau * 0.4)
    return mix(dur, (body, 0, 1.0), (grit, 0, 0.35))


def sfx_card_deal(rng):
    # A card sliding off the deck and landing: a short bandpassed noise flick
    # sweeping down (the edge across the felt), then a faint felt "thup".
    f_hi = rng.uniform(4200, 5200)
    flick = bandpass(noise(0.07, rng), lambda t: f_hi - 22000 * t, q=0.9)
    flick = shape_by(flick, lambda t: min(1.0, t / 0.008) * math.exp(-t / 0.022))
    land = thump(rng, 220, 120, 0.06, 0.012)
    return mix(0.14, (flick, 0, 1.0), (land, 0.035, 0.25)), -6.0


def sfx_card_flip(rng):
    # The snap of a card turned face up: two quick bright snaps, the second
    # (the card slapping down) lower and softer.
    snap1 = env(bandpass(noise(0.03, rng), 3200, q=1.4), 0.0005, 0.006)
    snap2 = env(bandpass(noise(0.05, rng), 1800, q=1.0), 0.0008, 0.012)
    air = shape_by(bandpass(noise(0.05, rng), lambda t: 2500 + 30000 * t, q=0.7),
                   lambda t: math.sin(math.pi * min(1.0, t / 0.05)) * 0.6)
    return mix(0.16, (snap1, 0, 1.0), (air, 0.008, 0.3), (snap2, 0.058, 0.7)), -6.0


def sfx_chips(rng):
    # A small bet: two to four chips dropped onto a stack.
    count = rng.choice([2, 3, 3, 4])
    t = 0.0
    parts = []
    base = rng.uniform(2800, 3300)
    for i in range(count):
        parts.append((clink(rng, base * rng.uniform(0.93, 1.08)), t, 1.0 * (0.85 ** i)))
        t += rng.uniform(0.035, 0.075)
    return mix(t + 0.12, *parts), -4.0


def sfx_chips_pot(rng):
    # The pot pushed to the winner: a stack's worth of clinks, thick in the
    # middle, over a soft lowpassed slide across the felt.
    dur = 0.85
    parts = []
    for _ in range(26):
        # Clustered toward the first half: a push, then stragglers settling.
        t = min(dur - 0.12, abs(rng.gauss(0.22, 0.14)))
        parts.append((clink(rng, rng.uniform(2500, 3900), rng.uniform(0.6, 1.0)), t, rng.uniform(0.35, 0.8)))
    slide = lowpass(bandpass(noise(dur, rng), 700, q=0.6), 1500)
    slide = shape_by(slide, lambda t: math.sin(math.pi * min(1.0, t / 0.6)) ** 2)
    parts.append((slide, 0.0, 2.2))
    return mix(dur, *parts), -3.0


def sfx_check(rng):
    # Knuckles on felt, twice: low, soft, no ring.
    k1 = thump(rng, 160, 85, 0.12, 0.03)
    k2 = thump(rng, 150, 80, 0.12, 0.03)
    return mix(0.30, (k1, 0, 1.0), (k2, 0.115, 0.8)), -4.0


def sfx_fold(rng):
    # Cards tossed into the muck: an airy whoosh, then a soft papery slap.
    whoosh = bandpass(noise(0.16, rng), lambda t: 1200 + 14000 * t, q=0.8)
    whoosh = shape_by(whoosh, lambda t: math.sin(math.pi * min(1.0, t / 0.16)) ** 2)
    slap = env(bandpass(noise(0.08, rng), 1400, q=0.8), 0.0008, 0.018)
    land = thump(rng, 170, 100, 0.08, 0.015)
    return mix(0.34, (whoosh, 0, 0.7), (slap, 0.14, 1.0), (land, 0.14, 0.35)), -5.0


def sfx_all_in(rng):
    # Everything in the middle: a rising major arpeggio of soft bell tones
    # over a shimmer of highpassed noise that swells, with the whole thing
    # gliding up a little. Climbs for ~0.6s, then rings out.
    dur = 0.95
    parts = []
    names = ["C5", "E5", "G5", "C6", "E6", "G6", "C7"]
    for i, nm in enumerate(names):
        f = note(nm)
        tone = partials(f, [1, 2, 3], [1.0, 0.25, 0.08], [0.35, 0.15, 0.07], dur - i * 0.075, attack=0.004)
        parts.append((tone, i * 0.075, 0.5 + 0.06 * i))
    shimmer = highpass(noise(dur, rng), 6000)
    shimmer = shape_by(shimmer, lambda t: (min(1.0, t / 0.55) ** 2) * (1.0 if t < 0.55 else math.exp(-(t - 0.55) / 0.08)))
    trem = osc(lambda t: 9 + 10 * t, dur)
    shimmer = [s * (0.6 + 0.4 * w) for s, w in zip(shimmer, trem)]
    parts.append((shimmer, 0, 0.18))
    swell = adsr(osc(lambda t: note("C4") * (1 + 0.5 * min(1.0, t / 0.6)), dur, "tri"), 0.3, 0.3, 0.5, 0.3)
    parts.append((swell, 0, 0.25))
    # Ring out over the last quarter second instead of being cut by the
    # end of the buffer (the first render ended at -6 dB: a click-free but
    # audible chop).
    out = shape_by(mix(dur, *parts), lambda t: 1.0 if t < 0.7 else math.cos(0.5 * math.pi * (t - 0.7) / (dur - 0.7)) ** 2)
    return out, -2.0


def sfx_win_pot(rng):
    # Cheerful chime: a quick rising C major arpeggio of bell-like tones with
    # clean harmonic partials, the top note held longest.
    dur = 0.95
    parts = []
    for i, nm in enumerate(["C6", "E6", "G6", "C7"]):
        tail = dur - i * 0.07
        tau = 0.22 if i < 3 else 0.32
        tone = partials(note(nm), [1, 2, 3, 4], [1.0, 0.3, 0.1, 0.04], [tau, tau * 0.5, tau * 0.3, tau * 0.2], tail, attack=0.002)
        parts.append((tone, i * 0.07, 1.0 if i == 3 else 0.75))
    # A soft octave-below body under the last note, so it's warm, not tinny.
    parts.append((partials(note("C5"), [1, 2], [1.0, 0.2], [0.3, 0.12], dur - 0.21, attack=0.01), 0.21, 0.35))
    return mix(dur, *parts), -1.5


def sfx_lose(rng):
    # Soft descending three notes (G4, E4, C4 on a round triangle), the last
    # sagging a little with a slow vibrato: "aw, shucks", not a sad trombone.
    parts = []
    for i, nm in enumerate(["G4", "E4", "C4"]):
        f = note(nm)
        last = i == 2
        d = 0.5 if last else 0.2
        fn = (lambda t, f=f: f * (1 - 0.03 * min(1.0, t / 0.45)) * (1 + 0.006 * math.sin(TAU * 5 * t))) if last else f
        tone = adsr(osc(fn, d, "tri", harmonics=4), 0.012, 0.08, 0.6, 0.12 if not last else 0.3)
        parts.append((lowpass(tone, 2500), i * 0.17, 1.0))
    return mix(0.9, *parts), -5.0


def sfx_your_turn(rng):
    # A gentle two-note ping (A5 then E6), marimba-soft: sine with a faint
    # octave that dies fast.
    a = partials(note("A5"), [1, 2, 4], [1.0, 0.2, 0.05], [0.12, 0.05, 0.02], 0.3, attack=0.003)
    b = partials(note("E6"), [1, 2, 4], [1.0, 0.2, 0.05], [0.2, 0.07, 0.025], 0.45, attack=0.003)
    return mix(0.55, (a, 0, 0.8), (b, 0.09, 1.0)), -5.0


def sfx_signal(rng):
    # A tiny rustle: a paw brushing fur or sleeve, a few soft noise grains.
    dur = 0.2
    parts = []
    t = 0.0
    while t < 0.13:
        g = env(bandpass(noise(0.03, rng), rng.uniform(2500, 5000), q=1.2), 0.004, 0.008)
        parts.append((g, t, rng.uniform(0.4, 1.0)))
        t += rng.uniform(0.012, 0.03)
    return mix(dur, *parts), -10.0


def sfx_dealer_warning(rng):
    # The dealer's desk bell: one firm "ding" with bell-like (inharmonic)
    # partials, lower than any chime the player hears for good news.
    f0 = 1180
    ding = partials(f0, [1.0, 2.0, 2.76, 5.4], [1.0, 0.3, 0.35, 0.1], [0.4, 0.22, 0.15, 0.06], 0.9, attack=0.0015)
    tap = env(highpass(noise(0.01, rng), 2000), 0.0003, 0.002)
    return mix(0.9, (ding, 0, 1.0), (tap, 0, 0.3)), -3.0


def sfx_fine(rng):
    # Cash register "ka-ching": a mechanical clunk, the bell, and coins
    # rattling in the drawer.
    clunk = mix(0.1, (thump(rng, 260, 120, 0.1, 0.02), 0, 1.0),
                (env(bandpass(noise(0.05, rng), 1600, q=2.0), 0.0005, 0.01), 0, 0.6))
    bell1 = partials(2350, [1.0, 2.0, 2.76, 4.1], [1.0, 0.35, 0.3, 0.1], [0.3, 0.15, 0.1, 0.05], 0.7, attack=0.001)
    bell2 = partials(2350 * 1.26, [1.0, 2.0, 2.76], [1.0, 0.3, 0.25], [0.28, 0.12, 0.08], 0.6, attack=0.001)
    parts = [(clunk, 0, 1.0), (bell1, 0.09, 0.7), (bell2, 0.13, 0.5)]
    for _ in range(6):
        parts.append((clink(rng, rng.uniform(4000, 5500), 0.7, 0.05), rng.uniform(0.14, 0.35), rng.uniform(0.15, 0.3)))
    return mix(0.85, *parts), -3.0


def sfx_ejection(rng):
    # The floor's referee whistle: a short blast and a long one. A whistle
    # is a near-sine with a fast "pea" trill and breath noise.
    def blast(dur):
        f = lambda t: 2650 * (1 + 0.012 * math.sin(TAU * 38 * t)) * (1 + 0.02 * min(1.0, t / 0.03))
        tone = osc(f, dur)
        trill = osc(38, dur)
        tone = [v * (0.75 + 0.25 * w) for v, w in zip(tone, trill)]
        breath = bandpass(noise(dur, rng), 2650, q=3.0)
        sig = mix(dur, (tone, 0, 1.0), (breath, 0, 0.35))
        return adsr(sig, 0.015, 0.05, 0.85, 0.04)
    return mix(0.9, (blast(0.14), 0, 1.0), (blast(0.52), 0.22, 1.0)), -4.0


def sfx_ui_move(rng):
    # Cursor tick: a 25 ms soft square blip. Quiet; it plays constantly.
    tone = osc(note("E6"), 0.035, "square", harmonics=3)
    return lowpass(env(tone, 0.001, 0.01), 5000), -12.0


def sfx_ui_confirm(rng):
    # Two blips up a fifth.
    a = env(osc(note("C6"), 0.06, "square", harmonics=3), 0.002, 0.03)
    b = env(osc(note("G6"), 0.12, "square", harmonics=3), 0.002, 0.045)
    return lowpass(mix(0.17, (a, 0, 0.8), (b, 0.055, 1.0)), 5000), -9.0


def sfx_ui_back(rng):
    # Two blips down, softer and rounder than confirm.
    a = env(osc(note("G5"), 0.06, "tri"), 0.002, 0.03)
    b = env(osc(note("C5"), 0.12, "tri"), 0.002, 0.045)
    return mix(0.17, (a, 0, 1.0), (b, 0.055, 0.9)), -10.0


def sfx_step_grass(rng):
    # Grass: a short crunchy burst of crackle grains, bright but soft.
    dur = 0.12
    parts = [(shape_by(bandpass(noise(dur, rng), rng.uniform(2800, 4200), q=0.7),
                       lambda t: min(1.0, t / 0.01) * math.exp(-t / 0.03)), 0, 0.6)]
    for _ in range(9):
        grain = env(highpass(noise(0.006, rng), 2500), 0.0003, 0.0015)
        parts.append((grain, rng.uniform(0.0, 0.06), rng.uniform(0.3, 0.8)))
    parts.append((thump(rng, 120, 70, 0.06, 0.012), 0, 0.25))
    return mix(dur, *parts), -9.0


def sfx_step_wood(rng):
    # Floorboards: a low knock with a hollow midrange resonance.
    dur = 0.14
    knock = thump(rng, rng.uniform(130, 160), 80, dur, 0.025)
    hollow = env(bandpass(noise(dur, rng), rng.uniform(480, 620), q=6.0), 0.0005, 0.03)
    tick = env(bandpass(noise(0.01, rng), 2500, q=1.0), 0.0003, 0.002)
    return mix(dur, (knock, 0, 1.0), (hollow, 0, 2.2), (tick, 0, 0.3)), -9.0


def sfx_encounter(rng):
    # The "!" sting when a rival spots you: a bright pop, a fast rising
    # arpeggio, then a held stab with a little vibrato. Short and punchy in
    # the trainer-spotted tradition, but on a lowpassed square, not a raw one.
    dur = 0.85
    parts = [(env(bandpass(noise(0.03, rng), 3000, q=0.8), 0.0005, 0.006), 0, 0.5)]
    for i, nm in enumerate(["E5", "G#5", "B5"]):
        tone = env(osc(note(nm), 0.07, "square", harmonics=4), 0.002, 0.04)
        parts.append((tone, 0.01 + i * 0.05, 0.6))
    for nm in ["E5", "G#5", "B5", "E6"]:
        f = note(nm)
        stab = osc(lambda t, f=f: f * (1 + 0.008 * math.sin(TAU * 6 * t) * min(1.0, t / 0.2)), 0.65, "square", harmonics=4)
        parts.append((adsr(stab, 0.004, 0.12, 0.45, 0.25), 0.17, 0.3))
    return lowpass(mix(dur, *parts), 4500), -3.0


# Voice blips: one tiny, characterful sound per species, for when an animal
# acts, signals, or is greeted in the overworld.

def sfx_voice_owl(rng):
    # "Hoo-hooo": a breathy, nearly pure tone, gliding up then sagging.
    def hoot(d, f0):
        f = lambda t: f0 * (1 + 0.06 * math.sin(math.pi * min(1.0, t / d)))
        tone = osc(f, d)
        tone = mix(d, (tone, 0, 1.0), (osc(lambda t: 2 * f(t), d), 0, 0.08))
        breath = lowpass(bandpass(noise(d, rng), f0 * 2, q=2.0), 2000)
        return adsr(mix(d, (tone, 0, 1.0), (breath, 0, 0.25)), 0.04, 0.05, 0.8, 0.08)
    return mix(0.62, (hoot(0.15, 400), 0, 0.85), (hoot(0.36, 380), 0.22, 1.0)), -9.0


def sfx_voice_goose(rng):
    # Honk: a nasal band-limited saw through two formants, a pitch bump and
    # a bit of jitter. Lowpassed so it's comic, not grating.
    def honk(d, f0):
        jitter = [rng.uniform(-1, 1) for _ in range(64)]
        f = lambda t: f0 * (1 + 0.12 * math.sin(math.pi * min(1.0, t / d))) * (1 + 0.015 * jitter[int(t * 300) % 64])
        src = osc(f, d, "saw", harmonics=16)
        voiced = mix(d, (bandpass(src, 1000, q=3.0), 0, 1.0), (bandpass(src, 2400, q=4.0), 0, 0.5), (src, 0, 0.15))
        return adsr(lowpass(voiced, 3500), 0.012, 0.04, 0.8, 0.05)
    return mix(0.42, (honk(0.15, 330), 0, 1.0), (honk(0.2, 300), 0.19, 0.9)), -5.0


def sfx_voice_cat(rng):
    # "Mrrp?": a rising voiced tone, rolled (amplitude-trilled at ~28 Hz),
    # through an "mm-ah" formant that opens as it rises.
    d = 0.3
    f = lambda t: 380 + 260 * (t / d) ** 1.5
    src = osc(f, d, "saw", harmonics=10)
    roll = osc(28, d)
    src = [v * (0.55 + 0.45 * r) for v, r in zip(src, roll)]
    voiced = mix(d, (bandpass(src, lambda t: 500 + 900 * (t / d), q=2.0), 0, 1.0), (bandpass(src, 2300, q=4.0), 0, 0.25))
    return adsr(lowpass(voiced, 3000), 0.02, 0.05, 0.85, 0.08), -5.0


def sfx_voice_raccoon(rng):
    # Chitter: a quick, uneven run of tiny downward chirps.
    parts = []
    t = 0.0
    for i in range(10):
        f0 = rng.uniform(2200, 2900) * (1.0 - 0.012 * i)
        d = rng.uniform(0.022, 0.035)
        chirp = env(osc(lambda tt, f0=f0: f0 * (1 - 4.0 * tt), d, "tri", harmonics=3), 0.002, 0.012)
        parts.append((chirp, t, rng.uniform(0.6, 1.0)))
        t += rng.uniform(0.032, 0.05)
    return lowpass(mix(t + 0.06, *parts), 6000), -5.0


def sfx_voice_squirrel(rng):
    # Chatter: fast "chk-chk-chk" bursts, each a noisy click with a high
    # squeak in it, at about 16 a second, the middle ones loudest.
    parts = []
    count = 8
    for i in range(count):
        t = i * 0.062 + rng.uniform(-0.005, 0.005)
        click = env(bandpass(noise(0.03, rng), rng.uniform(3500, 4500), q=1.5), 0.0008, 0.006)
        squeak = env(osc(lambda tt: 5200 - 30000 * tt, 0.025), 0.002, 0.006)
        body = mix(0.03, (click, 0, 1.0), (squeak, 0, 0.35))
        parts.append((body, t, 0.5 + 0.5 * math.sin(math.pi * (i + 0.5) / count)))
    return mix(count * 0.062 + 0.06, *parts), -4.0


def sfx_voice_possum(rng):
    # A short, soft hiss with a breathy swell and a tremble: more "go away"
    # than threat.
    d = 0.48
    hiss = bandpass(noise(d, rng), lambda t: 4200 + 1500 * math.sin(math.pi * t / d), q=0.9)
    hiss = mix(d, (hiss, 0, 1.0), (highpass(noise(d, rng), 6000), 0, 0.25))
    trem = osc(19, d)
    hiss = [v * (0.75 + 0.25 * w) for v, w in zip(hiss, trem)]
    return shape_by(hiss, lambda t: math.sin(math.pi * min(1.0, t / d)) ** 1.5), -7.0


# name -> (function, variants). Variants are separate takes with their own
# randomness (name, name_2, name_3...), for sounds that repeat back to back.
SOUNDS = {
    "card_deal": (sfx_card_deal, 3),
    "card_flip": (sfx_card_flip, 1),
    "chips": (sfx_chips, 3),
    "chips_pot": (sfx_chips_pot, 1),
    "check": (sfx_check, 1),
    "fold": (sfx_fold, 1),
    "all_in": (sfx_all_in, 1),
    "win_pot": (sfx_win_pot, 1),
    "lose": (sfx_lose, 1),
    "your_turn": (sfx_your_turn, 1),
    "signal": (sfx_signal, 2),
    "dealer_warning": (sfx_dealer_warning, 1),
    "fine": (sfx_fine, 1),
    "ejection": (sfx_ejection, 1),
    "ui_move": (sfx_ui_move, 1),
    "ui_confirm": (sfx_ui_confirm, 1),
    "ui_back": (sfx_ui_back, 1),
    "step_grass": (sfx_step_grass, 3),
    "step_wood": (sfx_step_wood, 3),
    "encounter": (sfx_encounter, 1),
    "voice_owl": (sfx_voice_owl, 1),
    "voice_goose": (sfx_voice_goose, 1),
    "voice_cat": (sfx_voice_cat, 1),
    "voice_raccoon": (sfx_voice_raccoon, 1),
    "voice_squirrel": (sfx_voice_squirrel, 1),
    "voice_possum": (sfx_voice_possum, 1),
}


def file_names(name, variants):
    return [name] + ["%s_%d" % (name, k) for k in range(2, variants + 1)]


# ---------------------------------------------------------------- the lounge loop

def make_music():
    """A modest lounge-jazz loop: 8 bars at 92 bpm, swung, ii-V-I-vi in F
    twice (Gm7 C7 Fmaj7 Dm7). Electric-piano chords (2-op FM, the classic
    Rhodes trick: a sine modulated at the same frequency, the modulation
    decaying faster than the note), a walking upright bass (sine plus a
    little second harmonic, plucked envelope), and brushes (swished noise on
    2 and 4) with a soft ride. It loops sample-exactly: the length is a whole
    number of bars and every note's tail that would run past the end is
    wrapped around to the start."""
    sr = 22050
    bpm = 92
    beat = 60.0 / bpm
    bars = 8
    total = ns(bars * 4 * beat, sr)
    out = [0.0] * total
    rng = random.Random(zlib.crc32(b"lounge"))

    def add(sig, start, g):
        o = int(start * sr)
        for i, v in enumerate(sig):
            out[(o + i) % total] += v * g

    def swing(b):  # beat position -> seconds, eighths swung 2:1
        whole = math.floor(b)
        frac = b - whole
        frac = frac * (2 / 3) / 0.5 if frac <= 0.5 else 2 / 3 + (frac - 0.5) * (1 / 3) / 0.5
        return (whole + frac) * beat

    def epiano(f, dur, vel):
        n = ns(dur, sr)
        o = [0.0] * n
        k_amp = math.exp(-1.0 / (0.9 * sr))
        k_mod = math.exp(-1.0 / (0.15 * sr))
        a, m = 1.0, 1.6
        w = TAU * f / sr
        for i in range(n):
            o[i] = a * math.sin(w * i + m * math.sin(w * i)) * vel
            a *= k_amp
            m *= k_mod
        for i in range(min(n, 60)):
            o[i] *= i / 60
        r = min(n, int(0.08 * sr))
        for i in range(r):
            o[n - 1 - i] *= i / r
        return o

    def bass(f, dur):
        n = ns(dur, sr)
        o = [0.0] * n
        w = TAU * f / sr
        a = 1.0
        k = math.exp(-1.0 / (0.35 * sr))
        for i in range(n):
            o[i] = a * (math.sin(w * i) + 0.25 * math.sin(2 * w * i) * a)
            a *= k
        for i in range(min(n, 40)):
            o[i] *= i / 40
        r = min(n, int(0.03 * sr))
        for i in range(r):
            o[n - 1 - i] *= i / r
        return o

    def m(nm):
        return note(nm)

    chords = [
        (["F3", "A#3", "D4", "A4"], ["G2", "A2", "A#2", "B2"]),   # Gm7 (F Bb D A: 7, 3, 5, 9)
        (["E3", "A#3", "D4", "G4"], ["C3", "E2", "G2", "A#2"]),   # C9 (E Bb D G: 3, 7, 9, 13)
        (["E3", "A3", "C4", "G4"], ["F2", "A2", "C3", "E3"]),     # Fmaj9-ish (E A C G)
        (["F3", "A3", "C4", "E4"], ["D3", "C3", "A2", "G#2"]),    # Dm9 (F A C E), chromatic lead back
    ]
    for bar in range(bars):
        voicing, walk = chords[bar % 4]
        b0 = bar * 4
        # Comping: Charleston rhythm (1, the "and" of 2), varied every other bar.
        hits = [(0.0, 1.2, 0.9), (1.5, 1.0, 0.7)] if bar % 2 == 0 else [(0.0, 0.6, 0.8), (2.5, 1.3, 0.75)]
        for pos, length, vel in hits:
            for j, nm in enumerate(voicing):
                add(epiano(m(nm), length * beat + 0.3, vel * rng.uniform(0.85, 1.0)), swing(b0 + pos) + j * 0.006, 0.16)
        for q, nm in enumerate(walk):
            add(bass(m(nm), beat * 0.95), swing(b0 + q), 0.32 * (1.0 if q == 0 else 0.85))
        # Brushes: a swish across each beat, accents on 2 and 4.
        for q in range(4):
            sw = shape_by(bandpass(noise(beat * 0.9, rng, sr), 3500, q=0.6, sr=sr),
                          lambda t: math.sin(math.pi * min(1.0, t / (beat * 0.9))) ** 2, sr=sr)
            add(sw, swing(b0 + q), 0.05 if q % 2 == 0 else 0.09)
            if q % 2 == 1:
                tap = env(bandpass(noise(0.08, rng, sr), 2200, q=0.9, sr=sr), 0.002, 0.03, sr=sr)
                add(tap, swing(b0 + q), 0.12)
        # Ride: "ding, ding-a ding" on 1, 2, and-of-2, 3, 4, and-of-4.
        for pos in (0, 1, 1.5, 2, 3, 3.5):
            ride = partials(5100, [1.0, 1.41, 1.83, 2.37], [1.0, 0.8, 0.6, 0.4], [0.25, 0.18, 0.12, 0.08], 0.5, sr=sr)
            ride = mix(0.5, (ride, 0, 0.3), (env(highpass(noise(0.5, rng, sr), 6000, sr=sr), 0.001, 0.12, sr=sr), 0, 0.5), sr=sr)
            add(ride, swing(b0 + pos), 0.03 if pos == int(pos) else 0.022)
    # Gentle warmth: a lowpass at 7 kHz, then normalize. No fades: it loops.
    out = lowpass(out, 7000, sr)
    out = lowpass(out, 7000, sr)
    out = highpass(out, 30.0, sr)
    peak = max(abs(v) for v in out)
    g = 10 ** (-3.0 / 20) / peak
    return [v * g for v in out], sr


# ---------------------------------------------------------------- measuring

def fft(x):
    """Iterative radix-2 FFT on a list of complex numbers (len a power of 2)."""
    n = len(x)
    a = list(x)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        half = size // 2
        step = complex(math.cos(-TAU / size), math.sin(-TAU / size))
        for start in range(0, n, size):
            w = 1 + 0j
            for k in range(start, start + half):
                t = w * a[k + half]
                a[k + half] = a[k] - t
                a[k] = a[k] + t
                w *= step
        size *= 2
    return a


def measure(x, sr):
    n = len(x)
    peak = max(abs(v) for v in x)
    rms = math.sqrt(sum(v * v for v in x) / n)
    dc = sum(x) / n
    # Edges: the first quarter millisecond (an attack may be fast, but must
    # start from zero) and the last two milliseconds (tails die out).
    head = max(abs(v) for v in x[:max(1, int(0.00025 * sr))])
    tail = max(abs(v) for v in x[-max(1, int(0.002 * sr)):])
    clipped = sum(1 for v in x if abs(v) >= 32767 / 32768.0)
    # Spectral centroid over the loudest 2048-sample window: where "bright" lives.
    size = 2048 if n >= 2048 else 1 << (n.bit_length() - 1)
    best, best_e = 0, -1.0
    for s in range(0, max(1, n - size), size // 2):
        e = sum(v * v for v in x[s:s + size])
        if e > best_e:
            best, best_e = s, e
    win = [x[best + i] * (0.5 - 0.5 * math.cos(TAU * i / size)) if best + i < n else 0.0 for i in range(size)]
    spec = fft(win)
    mags = [abs(c) for c in spec[:size // 2]]
    tot = sum(mags) or 1.0
    centroid = sum(m * k * sr / size for k, m in enumerate(mags)) / tot
    return {
        "dur": n / sr, "peak_db": 20 * math.log10(peak) if peak > 0 else -999.0,
        "rms_db": 20 * math.log10(rms) if rms > 0 else -999.0, "dc": dc,
        "head": head, "tail": tail, "clipped": clipped, "centroid": centroid,
    }


def check_row(name, mm, max_dur=1.0):
    problems = []
    if mm["dur"] > max_dur:
        problems.append("long")
    if mm["clipped"]:
        problems.append("clips")
    if mm["peak_db"] > -0.5:
        problems.append("hot")
    if abs(mm["dc"]) > 0.002:
        problems.append("dc")
    if mm["head"] > 0.01 or mm["tail"] > 0.01:
        problems.append("edge")
    return problems


def print_table(rows):
    print("%-18s %6s %8s %7s %9s %7s %7s %9s  %s" % ("sound", "sec", "peak dB", "rms dB", "dc", "start", "end", "centroid", "status"))
    bad = 0
    for name, mm, max_dur in rows:
        problems = check_row(name, mm, max_dur)
        bad += bool(problems)
        print("%-18s %6.3f %8.1f %7.1f %9.5f %7.4f %7.4f %7.0fHz  %s" % (
            name, mm["dur"], mm["peak_db"], mm["rms_db"], mm["dc"], mm["head"], mm["tail"], mm["centroid"],
            ", ".join(problems) or "ok"))
    return bad


# ---------------------------------------------------------------- previews

def png(path, width, height, pixels):
    """Minimal RGB PNG writer: pixels is a list of rows of (r, g, b)."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def heat_color(v):
    """0..1 -> black, purple, orange, pale yellow (a magma-like ramp)."""
    stops = [(0.0, (0, 0, 0)), (0.3, (60, 15, 110)), (0.6, (200, 60, 70)), (0.85, (250, 170, 60)), (1.0, (255, 250, 200))]
    v = min(1.0, max(0.0, v))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        if v <= p1:
            u = (v - p0) / (p1 - p0)
            return tuple(int(a + (b - a) * u) for a, b in zip(c0, c1))
    return stops[-1][1]


def render_strip(x, sr, px_per_sec=400, spec_h=128, wave_h=48, min_width=None):
    """Waveform (top) over a log-frequency spectrogram (50 Hz to 16 kHz,
    -80..0 dB), one column per 1/px_per_sec seconds. Faint lines mark
    100 ms in time and 1, 4 and 10 kHz in frequency."""
    width = max(min_width or 0, int(len(x) / sr * px_per_sec) + 1)
    size = 1024
    hop = sr / px_per_sec
    hann = [0.5 - 0.5 * math.cos(TAU * i / size) for i in range(size)]
    lo, hi = math.log(50), math.log(16000)
    bins = [min(size // 2 - 1, int(math.exp(lo + (hi - lo) * (1 - r / (spec_h - 1))) * size / sr)) for r in range(spec_h)]
    rows = [[(12, 12, 18)] * width for _ in range(wave_h + spec_h)]
    cols = int(len(x) / sr * px_per_sec) + 1
    for c in range(cols):
        centre = int(c * hop)
        s = centre - size // 2
        frame = [(x[s + i] if 0 <= s + i < len(x) else 0.0) * hann[i] for i in range(size)]
        mags = [abs(v) for v in fft(frame)[:size // 2]]
        for r in range(spec_h):
            db = 20 * math.log10(mags[bins[r]] / (size / 4) + 1e-9)
            rows[wave_h + r][c] = heat_color((db + 80) / 80)
        a = int(c * hop)
        b = min(len(x), int((c + 1) * hop) + 1)
        seg = x[a:b] or [0.0]
        top = int((1 - max(seg)) * (wave_h - 1) / 2)
        bot = int((1 - min(seg)) * (wave_h - 1) / 2)
        for r in range(max(0, top), min(wave_h, bot + 1)):
            rows[r][c] = (120, 200, 190)
    for c in range(0, width, max(1, px_per_sec // 10)):
        for r in range(wave_h + spec_h):
            if rows[r][c] == (12, 12, 18) or r >= wave_h:
                rows[r][c] = tuple(min(255, v + 25) for v in rows[r][c])
    for hz in (1000, 4000, 10000):
        r = int((1 - (math.log(hz) - lo) / (hi - lo)) * (spec_h - 1)) + wave_h
        for c in range(0, width, 2):
            rows[r][c] = (90, 90, 110)
    rows[wave_h // 2] = [(60, 60, 70) if p == (12, 12, 18) else p for p in rows[wave_h // 2]]
    return rows


def write_previews(out_dir, names):
    os.makedirs(out_dir, exist_ok=True)
    strips = []
    for name in names:
        x, sr = read_wav(os.path.join(SFX_DIR, name + ".wav"))
        rows = render_strip(x, sr, min_width=401)
        png(os.path.join(out_dir, name + ".png"), len(rows[0]), len(rows), rows)
        strips.append(rows)
    # A contact sheet: every sound at the same time scale, 1 s wide, stacked.
    width = 401
    sheet = []
    for rows in strips:
        for row in rows:
            sheet.append((row + [(12, 12, 18)] * width)[:width])
        sheet.append([(255, 255, 255)] * width)
    png(os.path.join(out_dir, "_sheet.png"), width, len(sheet), sheet)
    print("previews: %s (%d sounds, _sheet.png stacks them in this order: %s)" % (out_dir, len(names), ", ".join(names)))


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", nargs="*", help="sound names to (re)generate")
    ap.add_argument("--check", action="store_true", help="only measure the WAVs on disk")
    ap.add_argument("--preview", metavar="DIR", help="write a waveform + spectrogram PNG per sound")
    ap.add_argument("--music", action="store_true", help="also render the lounge loop")
    args = ap.parse_args()

    wanted = args.only or list(SOUNDS)
    unknown = [n for n in wanted if n not in SOUNDS]
    if unknown:
        sys.exit("unknown sound(s): %s" % ", ".join(unknown))
    if not args.check:
        for name in wanted:
            fn, variants = SOUNDS[name]
            for fname in file_names(name, variants):
                rng = random.Random(zlib.crc32(fname.encode()))
                x, peak_db = fn(rng)
                write_wav(os.path.join(SFX_DIR, fname + ".wav"), finish(x, peak_db))
        if args.music:
            x, sr = make_music()
            write_wav(os.path.join(MUSIC_DIR, "lounge_loop.wav"), x, sr)

    rows = []
    names = []
    for name in wanted:
        for fname in file_names(name, SOUNDS[name][1]):
            x, sr = read_wav(os.path.join(SFX_DIR, fname + ".wav"))
            rows.append((fname, measure(x, sr), 1.0))
            names.append(fname)
    loop = os.path.join(MUSIC_DIR, "lounge_loop.wav")
    if os.path.exists(loop) and not args.only:
        x, sr = read_wav(loop)
        mm = measure(x, sr)
        # A loop must not have silent edges; it must join: the jump across the seam should be no
        # bigger than an ordinary step inside the loop.
        seam = abs(x[0] - x[-1])
        typical = sorted(abs(b - a) for a, b in zip(x, x[1:]))[int(len(x) * 0.99)]
        print("lounge_loop: %.2fs at %d Hz, peak %.1f dB, rms %.1f dB, dc %.5f, seam jump %.4f (99th pct step %.4f) %s" % (
            mm["dur"], sr, mm["peak_db"], mm["rms_db"], mm["dc"], seam, typical, "ok" if seam <= typical and not mm["clipped"] else "CHECK"))
    total = sum(os.path.getsize(os.path.join(d, f)) for d in (SFX_DIR, MUSIC_DIR) if os.path.isdir(d) for f in os.listdir(d) if f.endswith(".wav"))
    bad = print_table(rows)
    print("%d files, %.2f MB of WAVs, %d with problems" % (len(rows), total / 1e6, bad))
    if args.preview:
        write_previews(args.preview, names)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
