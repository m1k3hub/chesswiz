# Patent review (2026-10-10)

An engineering inventory of the algorithms Chesswiz implements or ships, checked
against the patent families commonly known to affect them. This is **not** a
freedom-to-operate opinion: no patent database search was done. Treat
"no known patent" as "nothing well-known", and have a patent attorney review the
items under *Action* before a paid release, especially in the US.

## Action: media codecs in the Windows/macOS installers

The media pane plays ChessBase/Scidb lesson media (`.wmv`, `.asf`, `.mp4`,
`.mpeg`, `.mp3`, …) through **libmpv**, linked into `tkchesswiz` (`-lmpv` in
`src/Makefile`, `src/tcl/tcl_media.cpp`). libmpv decodes with FFmpeg's
libavcodec.

- **Linux:** libmpv and FFmpeg come from the distribution, which carries the
  codec question; nothing to do.
- **Windows/macOS:** the installers would *bundle* libmpv and FFmpeg, so
  Chesswiz itself would distribute decoders for codecs with live patent pools:

| Codec | Used by | Status (approximate; verify) |
|---|---|---|
| H.264 / AVC (MP4 lessons) | ChessBase video, `.mp4` | pool licensed (Via LA); last US patents run to about 2027–2030 |
| HEVC / H.265 | newer `.mp4` | several active pools (Access Advance, Via LA); patents into the 2030s |
| VC-1 / WMV9 (`.wmv`, `.asf`) | ChessBase lessons (most common) | pool licensed; most patents expired, some may remain |
| AAC (audio in `.mp4`) | ChessBase video | pool still licensing; most core patents expired |
| MP3, MPEG-1/2 video, MPEG-1/2 audio | older lessons | patents expired (MP3 2017, MPEG-2 2018) |
| VP8/VP9, AV1, Opus, Vorbis, FLAC, Theora | rare in chess media | royalty-free (AV1/VP9 have pool claims that haven't been enforced) |

**Decided (2026-10-10): option 1.** See D8 in `docs/dev/PORT_WINDOWS_MAC_SPEC.md`: `MEDIA_BACKEND=mf` (Windows) and `MEDIA_BACKEND=avf` (macOS).

Options, in order of preference:

1. **Decode through the operating system** on Windows/macOS: Media Foundation and
   AVFoundation/VideoToolbox. Microsoft and Apple hold the licences for H.264,
   HEVC, AAC and WMV. This means a second media backend beside libmpv (the media
   pane already wraps the transport behind `::media::*`). Recommended.
2. **Ship FFmpeg built with only patent-free decoders**
   (`--disable-decoders --enable-decoder=mp3,mpeg1video,mpeg2video,vp8,vp9,av1,opus,vorbis,flac,theora,pcm_*`)
   and hand everything else to the OS player, or show "open externally".
   Simple, but it loses in-app playback for the most common lesson formats.
3. **Keep the full FFmpeg** and take a licence from the relevant pools, or
   accept the risk. Not recommended for a paid product without legal advice.

Whatever is chosen, FFmpeg must be built **LGPL**, without `--enable-gpl` or
`--enable-nonfree` unless the GPL obligations are intended.

## Reviewed, no action

| Area | Code | Finding |
|---|---|---|
| JPEG decoding | `src/tk/jpeg` | Baseline/progressive **Huffman** only. Arithmetic coding (the once-patented mode) is only *named* in a lookup table (`jpeg_base.cpp:244-248`), not implemented; those patents expired by about 2007 anyway. |
| GIF / LZW | Tk's GIF reader | Unisys LZW patents expired 2003 (US) and 2004 (EU/JP). |
| Deflate, zip, gzip | zlib, minizip, zziplib | Deflate was designed to avoid patents; traditional PKZIP encryption isn't patented. No PKWARE "strong encryption" is implemented. |
| PDF encryption | `src/util/libharu/hpdf_encrypt.c` | RC4 (never patented; a former trade secret) and MD5. No AES code path. |
| Vector rendering | `src/tk/svg/agg` (Anti-Grain Geometry) | "Subpixel" there means sub-pixel *positioning* accuracy. There is no LCD/ClearType-style sub-pixel colour filtering, whose patents expired 2019 anyway. |
| Fonts | `.ttf` files, rendering by Tk/Xft/FreeType | TrueType bytecode-hinting patents (Apple) expired 2010; rendering is done by the platform. |
| Hyphenation | `src/util/libhyphenate` | Liang's TeX algorithm, published 1983, unpatented. |
| Charset detection | `universalchardet` | Mozilla's algorithm, open, no known patents. |
| Chess engines | Stockfish (NNUE), Sjeng, Reckless | Alpha-beta search and NNUE (Nasu 2018) are published openly. No known patents; GPL/AGPL code. |
| Tablebases and opening books | Polyglot books, Syzygy probing (in Stockfish) | Open formats, no known patents. |
| ChessBase formats (CBH/CBV/CBM) | `src/db/cbh` | Reverse-engineered for interoperability. That's a copyright and contract question (EU Software Directive art. 6, US DMCA §1201(f)), not a patent one. File formats themselves aren't patentable. No known ChessBase patents. |
| Search and query | CQL 6, position search, pattern index | CQL is open; position hashing (Zobrist 1970) is public. No known patents. |
| AI features | `tcl/ai-*.tcl` | Call external model APIs (TypeSafe, Ollama, etc.). The provider's terms govern; there's no local model code to review. |
| Text to speech | `app-voice.tcl` | Runs external espeak-ng / OS voices; nothing bundled. |

## Follow-up

- D8 in `docs/dev/PORT_WINDOWS_MAC_SPEC.md` should record the media backend decision
  (OS decoders vs. a restricted FFmpeg) before the installers are built.
- Re-check this list when new decoders or file formats are added.
