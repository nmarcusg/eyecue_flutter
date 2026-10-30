# Icon generation

Every launcher, adaptive, monochrome and store icon in this tree is generated
from one file — [`assets/logo.png`](../assets/logo.png) — by
[`tool/generate_icons.py`](../tool/generate_icons.py). No icon is hand-edited and
no generative tool was used: the mark is only letterboxed onto a square canvas
and downscaled. Never edit a generated PNG; change the source or the script and
regenerate.

## 1. Source

| Property | Value |
| --- | --- |
| Path | `assets/logo.png` |
| SHA-256 | `0d044397e6a3d2b1e6592cbfc5dee8684538e361d75b4e9509bb90437b90d3c2` |
| Canvas | 512 × 545 px, RGBA (the source itself is non-square) |
| Ink bounding box | (50, 54) – (437, 491) → **387 × 437 px** |
| Ink aspect (w/h) | **0.8856** |
| Worst-case ink radius | 222.78 px from the ink centre |
| Mark colours | `#0A0A0A` (`kHomeInk`) and `#22C7F2` (`kHomeAccentCyan`) |

Both mark colours are existing tokens in
[`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:82); the artwork is not
recoloured.

## 2. Tooling

`python3` + **Pillow 11.3.0**, already installed on the build host. Pillow was
chosen over the other candidates because it gives deterministic, explicit control
of the letterbox maths, the alpha channel and LANCZOS downscaling:

- ImageMagick 7.1.1 is also present; not used (no advantage here, and its PNG
  writer emits extra chunks that make byte-for-byte reproducibility harder to
  argue).
- `rsvg-convert` is not installed — not needed, the source is a PNG, not SVG.
- The in-repo PNG encoder ([`lib/models/png_encoder.dart`](../lib/models/png_encoder.dart))
  was the fallback if no image tool existed: it encodes but does not decode or
  resample, so using it would have meant writing a downscaler too.

Pillow is a **host tool, not a project dependency**: nothing is added to
[`pubspec.yaml`](../pubspec.yaml) and the script installs nothing. If it is
missing on another machine, that is an environment gap, not an app dependency.

## 3. Command

```sh
python3 tool/generate_icons.py            # write every asset, then verify it
python3 tool/generate_icons.py --check    # verify the committed files, write nothing
```

Both modes end with the same assertions and print every output hash. Exit code
is non-zero on any failure. The script is idempotent: running it twice produces
byte-identical files (verified — `sha256sum` identical across two runs).

## 4. Geometry

One rule drives every raster target — the ink keeps the source aspect ratio
(0.8856) and is centred, never stretched:

| Target | Canvas | Ink longest side | Padding / constraint |
| --- | --- | --- | --- |
| Legacy `ic_launcher.png`, `ic_launcher_round.png` | 48 / 72 / 96 / 144 / 192 px | 78 % of the canvas (37.4 / 56.2 / 74.9 / 112.3 / 149.8 px) | 11 % on each side — inside the 10–12 % band |
| Adaptive `ic_launcher_foreground.png`, `ic_launcher_monochrome.png` | 108 / 162 / 216 / 324 / 432 px (108 dp) | 60.8 / 91.2 / 121.6 / 182.4 / 243.2 px (60.8 dp) | ink scaled to a **31 dp radius**, measured extent 31.1–32.0 dp, inside the **66 dp safe zone** (33 dp radius) at every density |
| Play icon | 512 × 512 px | 399.4 px | 11 % on each side, 32-bit RGBA |
| Feature graphic | 1024 × 500 px | 260 px inside a white panel | dark field `#121212`, no alpha |

Why 31 dp rather than 33 dp for the adaptive foreground: resampling widens the
outermost anti-aliased pixels by up to one mdpi pixel (1 dp), so targeting the
33 dp radius exactly left the measured extent on the boundary. One dp of
clearance keeps the measured worst case at 32.0 dp, and the checker asserts the
33 dp limit with no tolerance.

No target upscales: the largest ink ever drawn is the 512 Play icon at 399.4 px,
below the 437 px source ink.

## 5. Colours and layers

| Layer | File | Value |
| --- | --- | --- |
| Adaptive background | [`mipmap-anydpi-v26/ic_launcher.xml`](../android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml) → `@color/ic_launcher_background` | `#FFFFFF` — `kHomeSurfaceCard` |
| Legacy / Play background | baked into the PNG | the same `#FFFFFF` |
| Monochrome | `ic_launcher_monochrome.png` | single colour `#FFFFFF` silhouette from the logo's own alpha; the system tints it |

`#FFFFFF` is the only palette value that keeps both strokes of the mark visible:
its outline is `#0A0A0A`, which would disappear on `kScaffoldBackground`
(`#121212`). The mark is not recoloured to suit a dark background.

The legacy PNGs therefore carry the light background instead of a transparent
one. The contract's default was "transparent unless the logo already carries its
own"; this mark does not, and a transparent black glyph is invisible on a dark
wallpaper, so the same palette background as the adaptive layer is used for
consistency between launchers that do and do not support adaptive icons.

The monochrome layer is the only place where a single-colour silhouette is
acceptable: it is a system-mask asset that Android re-tints, not the identity
asset. The colour artwork stays in `ic_launcher*.png` and in the Play icon.

## 6. Outputs and hashes

Generated by the command in §3, with the source hash above. `sha256` values are
of the committed files.

| File | Size | SHA-256 |
| --- | --- | --- |
| `mipmap-mdpi/ic_launcher.png` | 48 × 48 | `7cc53ffe254a293f08daaac5a53378750acc5891316fdd9c98caf3fea51bf870` |
| `mipmap-hdpi/ic_launcher.png` | 72 × 72 | `3d933bf36beabee3b4acc7bf2452194c71e6b3a902085390bcac7ce7efda6e83` |
| `mipmap-xhdpi/ic_launcher.png` | 96 × 96 | `57d038db2c6c6659c5807fb2ce3fbdf4c837510d449d11e665169a1167868d99` |
| `mipmap-xxhdpi/ic_launcher.png` | 144 × 144 | `e3cccd848216a77623584b56f1ccb7e086634bbebb08a26e9bd75ea63f8897d0` |
| `mipmap-xxxhdpi/ic_launcher.png` | 192 × 192 | `6386a5d4ef0de9fedc2322e0d49e147a2031f3414ac47dc585d99091dac1845d` |
| `mipmap-mdpi/ic_launcher_round.png` | 48 × 48 | `7cc53ffe254a293f08daaac5a53378750acc5891316fdd9c98caf3fea51bf870` |
| `mipmap-hdpi/ic_launcher_round.png` | 72 × 72 | `3d933bf36beabee3b4acc7bf2452194c71e6b3a902085390bcac7ce7efda6e83` |
| `mipmap-xhdpi/ic_launcher_round.png` | 96 × 96 | `57d038db2c6c6659c5807fb2ce3fbdf4c837510d449d11e665169a1167868d99` |
| `mipmap-xxhdpi/ic_launcher_round.png` | 144 × 144 | `e3cccd848216a77623584b56f1ccb7e086634bbebb08a26e9bd75ea63f8897d0` |
| `mipmap-xxxhdpi/ic_launcher_round.png` | 192 × 192 | `6386a5d4ef0de9fedc2322e0d49e147a2031f3414ac47dc585d99091dac1845d` |
| `mipmap-mdpi/ic_launcher_foreground.png` | 108 × 108 | `edaab134fabbfa2a7786f678a4cc035587c0ed1c2abc6662c59a450112772211` |
| `mipmap-hdpi/ic_launcher_foreground.png` | 162 × 162 | `8c9bf54d9264e8b90c3da30a4a76b3a27aab907bcd2141be0400a43686695448` |
| `mipmap-xhdpi/ic_launcher_foreground.png` | 216 × 216 | `a3a6550245eadf1e391746aea1d4ce70fca2435fdec585dca4e875e32b409aa1` |
| `mipmap-xxhdpi/ic_launcher_foreground.png` | 324 × 324 | `5bc4c9ec2d9359ed16acb2744f62c9d013fa96c2f8681437fdd67d037fc2caf2` |
| `mipmap-xxxhdpi/ic_launcher_foreground.png` | 432 × 432 | `bff7a7d74795d47642542087d0db0342086237abd33b67569fac41235e424105` |
| `mipmap-mdpi/ic_launcher_monochrome.png` | 108 × 108 | `0bcbfbae03b448d61854fe910eeb7b06527f222d69204274e97e42e8c98b4382` |
| `mipmap-hdpi/ic_launcher_monochrome.png` | 162 × 162 | `8c1aa4a9c4213379aadac920ac6ad57adbab5e7a6a18ff66ca171cb99ed5e751` |
| `mipmap-xhdpi/ic_launcher_monochrome.png` | 216 × 216 | `edc7e723ea24933815aeec5503dd03e28440659c3c6150c86e96b577f9b04a23` |
| `mipmap-xxhdpi/ic_launcher_monochrome.png` | 324 × 324 | `7ac5f253c45237670ccc1f83b6e2e144f121b1fa6b23f8277b312941b1beea9d` |
| `mipmap-xxxhdpi/ic_launcher_monochrome.png` | 432 × 432 | `73454e8460bf5c630fc3eba780c047729134649d8243c656eac957f203a6f4f3` |
| `store-assets/play-icon-512.png` | 512 × 512 | `f86ac73a55ad74346c5a615d3963e128b9eaffd39ebf03386e3f213c54c3b992` |
| `store-assets/feature-graphic-1024x500.png` | 1024 × 500 | `293fdabdefca377624ae55efef446ee9a6554ecb16fe99fe08911242776c0397` |

`ic_launcher_round.png` is byte-identical to `ic_launcher.png` at the same
density: the ink's worst-case radius is 0.40 × the canvas, so no circular launcher
mask can clip it — the round variant needs no different artwork.

`AndroidManifest.xml` references `@mipmap/ic_launcher` and
`@mipmap/ic_launcher_round`; `mipmap-anydpi-v26/ic_launcher.xml` and
`ic_launcher_round.xml` add the foreground + background + monochrome layers for
API 26 and later (the legacy PNGs are the fallback below that).

## 7. What the checker asserts

`tool/generate_icons.py` (in either mode) fails if any of these is false:

1. every launcher PNG is the expected pixel size for its density bucket
   (48/72/96/144/192 for legacy and round, 108/162/216/324/432 for the adaptive
   foreground and monochrome layers);
2. `store-assets/play-icon-512.png` is exactly 512 × 512 and has an alpha channel
   (RGBA, 8-bit/channel);
3. every raster icon is RGBA; the feature graphic is RGB with no alpha;
4. the **ink bounding box** aspect — measured on the ink, not the canvas — is
   within 0.02 of the source's 0.8856, so no target is stretched;
5. the ink is centred within 1 px and never touches the canvas edge (no clipping);
6. the ink's longest side matches the intended padding (legacy / Play) or the
   adaptive safe-zone scale (foreground, monochrome) within 2 px;
7. the adaptive foreground's worst-case ink radius in px is **≤ 33 dp** at that
   density's scale, i.e. inside the 66 dp safe zone;
8. the monochrome layer contains exactly one RGB colour.

Ran at the commit that added this file: all 21 icons + the feature graphic pass.
