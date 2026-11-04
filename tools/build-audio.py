"""Build the x64 audio DLL from four mono WAV files."""
import argparse
from pathlib import Path
import subprocess
import wave

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--audio", type=Path, default=Path("build/audio"))
parser.add_argument("--output", type=Path, default=Path("build/native"))
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
clips = ("SW_DungRelease", "SW_DungImpact", "SW_StalkRelease", "SW_StalkImpact")
for index, name in enumerate(clips, 101):
    with wave.open(str(args.audio / (name + ".wav"))) as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 48000):
            raise ValueError(f"{name} must be 48 kHz mono 16-bit PCM")
        (out / f"{index}.pcm").write_bytes(source.readframes(source.getnframes()))
(out / "sounds.rc").write_text(
    "".join(f'{index} RCDATA "{index}.pcm"\n' for index in range(101, 105)), encoding="ascii"
)
subprocess.run(["rc", "/nologo", "/fo", "sounds.res", "sounds.rc"], cwd=out, check=True)
subprocess.run([
    "cl", "/nologo", "/O2", "/MT", "/W4", "/LD", "/std:c++17", "/Fe:PBZThrowAudio.dll",
    str(root / "src/PBZThrowAudio.cpp"), "sounds.res", "xaudio2.lib", "ole32.lib",
    "/link", "/MACHINE:X64", "/DYNAMICBASE", "/NXCOMPAT", "/OPT:REF",
], cwd=out, check=True)
print(out / "PBZThrowAudio.dll")
