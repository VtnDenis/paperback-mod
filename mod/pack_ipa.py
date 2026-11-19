"""Turn the stock Paperback.app into a patched, tweak-injected bundle and zip it
as an IPA ready for a signer (Feather, Sideloadly, AltStore).

    python pack_ipa.py <Payload/Paperback.app> <out.ipa> [--dylib PaperbackMod.dylib]

What it changes:
  Info.plist  UIBackgroundModes += audio         keep-alive for downloads
              UIDesignRequiresCompatibility=false  (harmless on an 18.4-SDK build)
  bundle      zsign injects PaperbackMod.dylib, ad-hoc signs every Mach-O and
              regenerates _CodeSignature (the shipped one is stale once the plist
              and the executable change), so signers only have to swap our
              signature for theirs instead of fixing an inconsistent bundle.
"""

import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ZSIGN = Path(__file__).parents[1] / "_tools" / "zsign" / "zsign.exe"


def patch_plist(app: Path) -> None:
    path = app / "Info.plist"
    with path.open("rb") as fh:
        info = plistlib.load(fh)
    modes = set(info.get("UIBackgroundModes", []))
    modes.add("audio")
    info["UIBackgroundModes"] = sorted(modes)
    info["UIDesignRequiresCompatibility"] = False
    with path.open("wb") as fh:
        plistlib.dump(info, fh, fmt=plistlib.FMT_BINARY)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dylib = Path(__file__).with_name("PaperbackMod.dylib")
    if "--dylib" in sys.argv:
        dylib = Path(sys.argv[sys.argv.index("--dylib") + 1])
        args = [a for a in args if a != str(dylib)]
    src, out = Path(args[0]), Path(args[1])
    if not dylib.exists():
        raise SystemExit(f"missing {dylib} — run _tools/build_dylib.sh first")
    if not ZSIGN.exists():
        raise SystemExit(f"missing {ZSIGN}")

    with tempfile.TemporaryDirectory() as tmp:
        out.parent.mkdir(parents=True, exist_ok=True)
        payload = Path(tmp) / "Payload"
        app = payload / src.name
        shutil.copytree(src, app)
        patch_plist(app)
        shutil.rmtree(app / "_CodeSignature", ignore_errors=True)

        # zsign needs the folder name to end with .app, hence the copy above.
        subprocess.run([str(ZSIGN), "-a", "-f", "-l", str(dylib.resolve()), str(app)],
                       check=True)

        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(p for p in app.rglob("*") if p.is_file()):
                arc = path.relative_to(tmp).as_posix()
                info = zipfile.ZipInfo(arc)
                info.external_attr = 0o755 << 16
                zf.writestr(info, path.read_bytes())
    print("wrote", out, out.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
