#!/usr/bin/env python3
"""Paint the Encrypchat mark onto every launcher the installers ship.

The source is assets/brand/logo-mark.png — the shield, not the wordmark. App
icons have to be square, so this places that mark on a white canvas (the brand
background) and writes the densities each platform asks for. Re-run after the
mark changes; do not edit the generated files by hand.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MARK = ROOT / "apps/client/assets/brand/logo-mark.png"
MASTER = ROOT / "apps/client/assets/brand/app-icon.png"
# Navy canvas would hide the shield's own navy. White is the approved brand
# ground and what Android/iOS want behind a mask.
GROUND = (255, 255, 255, 255)
# Leave room so a circular launcher mask does not clip the shield points.
PADDING = 0.12


def square_icon(source: Image.Image, size: int, padding: float = PADDING) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), GROUND)
    inner = max(1, int(size * (1 - 2 * padding)))
    mark = source.copy()
    mark.thumbnail((inner, inner), Image.Resampling.LANCZOS)
    x = (size - mark.width) // 2
    y = (size - mark.height) // 2
    canvas.alpha_composite(mark, (x, y))
    return canvas


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def main() -> None:
    mark = Image.open(MARK).convert("RGBA")
    master = square_icon(mark, 1024)
    write_png(master, MASTER)

    android = ROOT / "apps/client/android/app/src/main/res"
    for name, px in (
        ("mipmap-mdpi", 48),
        ("mipmap-hdpi", 72),
        ("mipmap-xhdpi", 96),
        ("mipmap-xxhdpi", 144),
        ("mipmap-xxxhdpi", 192),
    ):
        write_png(square_icon(mark, px), android / name / "ic_launcher.png")

    # Adaptive: white plate + the mark inset so the system mask keeps the tips.
    (android / "drawable" / "ic_launcher_background.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FFFFFF"/>
</shape>
""",
        encoding="utf-8",
    )
    anydpi = android / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    for name, px in (
        ("mipmap-mdpi", 108),
        ("mipmap-hdpi", 162),
        ("mipmap-xhdpi", 216),
        ("mipmap-xxhdpi", 324),
        ("mipmap-xxxhdpi", 432),
    ):
        write_png(
            square_icon(mark, px, padding=0.18),
            android / name / "ic_launcher_foreground.png",
        )

    ios = ROOT / "apps/client/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for filename, px in (
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    ):
        write_png(square_icon(mark, px), ios / filename)

    ico = ROOT / "apps/client/windows/runner/resources/app_icon.ico"
    sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
    master.save(ico, format="ICO", sizes=sizes)

    print(f"master {MASTER.relative_to(ROOT)} {master.size}")
    print(f"windows {ico.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
