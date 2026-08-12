# Manrope, self-hosted

`manrope-latin-var.woff2` is loaded with `next/font/local` from `src/app/[locale]/layout.tsx`.

It used to be `next/font/google`, which downloads from `fonts.gstatic.com` **at build time**.
That made `next build` fail without network — and cascade into unrelated errors such as
`Cannot find module for page: /sitemap.xml` — so the file lives in the repo instead. Visitors
were always served the font from our own domain; now the build does not touch Google either.

## Provenance

| Item | Value |
| --- | --- |
| Upstream | `github.com/google/fonts` → `ofl/manrope/Manrope[wght].ttf` (SHA-256 `d0639be4…f8b0a40`) |
| License | SIL Open Font License 1.1 — [`OFL.txt`](OFL.txt), redistributed with the font as the license requires |
| Axis | `wght` clipped to `400..700` (the site uses 400, 600 and 700) |
| Charset | Google's `latin` subset range, plus `U+2192` (→, used on `/download`) |
| Size | 22 352 B (Google's equivalent `latin` file was 24 576 B) |

`latin-ext`, `cyrillic`, `cyrillic-ext`, `greek` and `vietnamese` are deliberately absent: the
rendered ES and EN pages use 96 distinct codepoints and **none** of them falls outside the
`latin` range. `U+2713` (✓) also falls outside it, but Manrope has no glyph for it, so it comes
from the system font either way.

## Regenerating

Needs `fonttools` and `brotli` (`pip install fonttools brotli`). Run from a scratch directory:

```bash
curl -fsSLO "https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf"
curl -fsSL -o OFL.txt "https://github.com/google/fonts/raw/main/ofl/manrope/OFL.txt"

python3 -m fontTools.varLib.instancer "Manrope[wght].ttf" wght=400:700 -o clipped.ttf

pyftsubset clipped.ttf --flavor=woff2 --output-file=manrope-latin-var.woff2 \
  --unicodes="U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,\
U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191-2193,U+2212,U+2215,U+FEFF,U+FFFD"
```

If new copy ever needs a character outside that range it will silently fall back to the system
font. Re-run the subset with the extra codepoints instead of adding a second file: one
`@font-face` with no `unicode-range` is what keeps the preload down to a single request.
