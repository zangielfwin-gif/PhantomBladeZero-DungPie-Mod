"""Decode the local DS3 bank and prepare short mono clips for spatial playback."""
import argparse
from array import array
import math
from pathlib import Path
import struct
import subprocess
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bank", type=Path, help="Path to DARK SOULS III/Game/sound/fdp_main.fsb")
parser.add_argument("vgmstream", type=Path, help="Path to vgmstream-cli.exe")
parser.add_argument("--output", type=Path, default=Path("build/audio"))
args = parser.parse_args()
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=True)
bank = args.bank.resolve()
cli = args.vgmstream.resolve()
rate = 48000


def decode(index, name):
    output = root / f"source-{index}.wav"
    result = subprocess.run([str(cli), "-i", "-W", "4", "-s", str(index), "-o", str(output), str(bank)],
                            check=True, text=True, capture_output=True)
    assert f"/{name}.wav" in result.stdout, result.stdout
    data = output.read_bytes()
    chunks = {}
    offset = 12
    while offset + 8 <= len(data):
        tag, size = struct.unpack_from("<4sI", data, offset)
        chunks[tag] = data[offset + 8:offset + 8 + size]
        offset += 8 + size + (size & 1)
    fmt, channels, hz, _, _, bits = struct.unpack_from("<HHIIHH", chunks[b"fmt "])
    assert fmt in (3, 0xFFFE) and channels == 1 and bits == 32
    return hz, array("f", chunks[b"data"])


def segment(source, start, duration, pitch=1, fade=.04, peak=1):
    hz, data = source
    samples = array("f")
    for i in range(round(duration * rate)):
        cursor = (start + i * pitch / rate) * hz
        j = int(cursor)
        if j + 1 >= len(data):
            break
        value = data[j] + (data[j+1] - data[j]) * (cursor - j)
        samples.append(value)
    gain = peak / max(map(abs, samples))
    return [v * gain * min(1, i / 90, (len(samples) - 1 - i) / (fade * rate))
            for i, v in enumerate(samples)]


def save(name, *layers):
    result = [0.] * max(round(offset * rate) + len(samples) for offset, samples in layers)
    for offset, samples in layers:
        for i, value in enumerate(samples, round(offset * rate)):
            result[i] += value
    assert 0.1 < max(map(abs, result)) < 0.99
    with wave.open(str(root / f"{name}.wav"), "wb") as f:
        f.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        f.writeframes(array("h", (round(v * 32767) for v in result)).tobytes())
    print(f"{name}: {len(result)/rate:.3f}s, peak {20*math.log10(max(map(abs, result))):.1f} dBFS")


throw = decode(1215, "swing-throw")
dung_impact = decode(820, "s000300102")
dung_impact_alt = decode(821, "s000300102b")
stalk = decode(765, "s300190000")
save("SW_DungRelease", (0, segment(throw, .005, .21, fade=.025, peak=.58)))
save("SW_DungImpact", (0, segment(dung_impact, 0, 1.55, fade=.19, peak=.79)))
save("SW_StalkRelease", (0, segment(throw, .013, .19, pitch=.82, fade=.05, peak=.43)),
     (.024, segment(dung_impact_alt, 0, .072, pitch=1.17, fade=.048, peak=.16)))
save("SW_StalkImpact", (0, segment(stalk, 0, 1.12, fade=.28, peak=.66)),
     (.008, segment(dung_impact_alt, 0, .54, fade=.18, peak=.31)))
