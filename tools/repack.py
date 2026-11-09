"""Assemble a new installer from locally built code and a released asset payload."""
import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path, help="Official project installer ZIP")
parser.add_argument("--dll", type=Path, help="Use a rebuilt audio DLL instead of the release DLL")
parser.add_argument("--output", type=Path, default=Path("dist/Better_PointDown_Snacks_AutoInstall.zip"))
args = parser.parse_args()
if args.output.resolve() == args.baseline.resolve():
    parser.error("Use a different output path from the baseline.")

root = Path(__file__).resolve().parent.parent
mod = "Mod/platform/steam/ue4ss/Mods/PBZThrowTest/Scripts"
paks = "Mod/ProjectPBZ/Content/Paks/~mods"
steam = "UE4SS_FirstInstall/platform/steam"
loader = f"{steam}/ue4ss"
resource_files = [
    f"{paks}/{stem}.{ext}"
    for stem in ("PBZThrowTest_P", "PBZThrowPropsSafe_P", "PointDownNative_LocalTest_P", "PBZActionMenu_P")
    for ext in ("pak", "utoc", "ucas")
]
resource_files.append(f"{steam}/dwmapi.dll")
resource_files.extend(f"{loader}/{name}" for name in (
    "UE4SS.dll", "UE4SS-settings.ini", "MemberVariableLayout.ini", "LICENSE",
    "UE4SS_Signatures/GNatives.lua", "UE4SS_Signatures/GUObjectArray.lua",
    "Mods/shared/UEHelpers/UEHelpers.lua", "Mods/mods.txt", "Mods/mods.json",
))

with ZipFile(args.baseline) as source:
    payload = {name: source.read(name) for name in resource_files}
    audio = f"{mod}/PBZThrowAudio.dll"
    payload[audio] = args.dll.read_bytes() if args.dll else source.read(audio)
payload[f"{mod}/main.lua"] = (root / "src/main.lua").read_bytes()
for name in ("Manage_Mod.ps1", "Install_Mod.cmd", "Uninstall_Mod.cmd"):
    encoding = "utf-8-sig" if name.endswith(".ps1") else "ascii"
    content = (root / "installer" / name).read_text(encoding=encoding)
    payload[name] = content.replace("\n", "\r\n").encode(encoding)
readme = (root / "使用说明.txt").read_text(encoding="utf-8-sig")
payload["使用说明.txt"] = readme.replace("\n", "\r\n").encode("utf-8-sig")

args.output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(args.output, "w", ZIP_DEFLATED, compresslevel=9) as release:
    for name, data in payload.items():
        release.writestr(name, data)
with ZipFile(args.output) as release:
    assert release.testzip() is None
print(args.output)
