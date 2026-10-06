---
name: ffmpeg
description: Process audio and video with ffmpeg and ffprobe. Use when converting, trimming, scaling, extracting frames or audio, or inspecting media files.
---

# FFmpeg

`ffmpeg -h full`, `ffmpeg -encoders` and `ffmpeg -h encoder=<name>` answer flag questions.
On the laptop `ffmpeg` and `ffprobe` come from the Nix system profile. Never install them
with a system package manager; if they are missing, say so.

## What goes wrong

- **Seeking.** `-ss` before `-i` seeks fast to the nearest keyframe; with `-c copy` the cut
  lands on a keyframe, not the exact time. Re-encode for a precise cut.
- **`-c copy` across containers** fails when the target container cannot hold the codec
  (WebM takes only VP8, VP9 or AV1 with Vorbis or Opus; MKV subtitles into MP4
  need `-c:s mov_text`). Re-encode the stream that does not fit.
- **CRF belongs to software encoders.** `libx264` (17 to 28, default 23), `libx265`
  (default 28), `libvpx-vp9` with `-crf 30 -b:v 0`. NVENC ignores `-crf`; use
  `-rc vbr -cq 23`. QSV uses `-global_quality`.
- **Compatibility.** For playback everywhere, `-c:v libx264 -pix_fmt yuv420p -c:a aac`, and
  `-movflags +faststart` for web MP4.
- **`cropdetect` only detects.** It prints a `crop=w:h:x:y` suggestion in the log; apply it
  in a second pass:

  ```bash
  ffmpeg -i in.mp4 -vf cropdetect -f null - 2>&1 | grep -o 'crop=[0-9:]*' | tail -1
  ffmpeg -i in.mp4 -vf crop=<w:h:x:y> out.mp4
  ```

- **Scaling** with `-1` can yield an odd dimension that `libx264` rejects; use `-2`
  (`scale=1280:-2`).
- **Speed changes** need both streams: `-vf "setpts=0.5*PTS" -af "atempo=2.0"`.
- **Concatenation:** the concat demuxer (`-f concat -safe 0 -i list.txt -c copy`) only joins
  files with identical codecs and parameters; otherwise use the `concat` filter.

## Frames and probing

```bash
ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 in.mp4
ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 in.mp4
ffmpeg -ss 5 -i in.mp4 -frames:v 1 frame.png                 # one frame at 5s
ffmpeg -i in.mp4 -vf fps=1 frame_%04d.png                    # one frame per second
ffmpeg -i in.mp4 -vf "fps=15,scale=640:-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" out.gif
```
