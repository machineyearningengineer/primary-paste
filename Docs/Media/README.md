# Product media

Real interaction, short captions, no stock art or soundtrack.

| File | Contents |
| --- | --- |
| `Explainer/Primary-Paste.gif` | README loop: 7.4 seconds, 960×375, 15 fps. |
| `Explainer/Primary-Paste.mp4` | Silent H.264 demo: 1280×500, 30 fps. Real Safari → TextEdit selection and paste. |
| `hero.png` | Result frame from the same edit at 6 seconds. |
| `onboarding.png` | Native Setup window, 880×712; no surrounding desktop. |
| `first-paste.png` | Native Safari practice window after verified paste, 880×752. |
| `icon.png` | Original app icon from `Scripts/generate_app_icon.swift`. |
| `architecture.svg` | Editable vector diagram of capture, paste delivery and conditional clipboard restoration. |
| `Explainer/Primary-Paste.tsrct` | Portable Tesseract 0.3.1 project with embedded footage/font and editable overlays. |
| `Explainer/Footage/Demo.mp4` | Full 18.033-second guest recording, without audio. |
| `Explainer/Fixtures/` | Original meeting-note HTML and TextEdit draft used for capture. |
| `Explainer/Previews/Filmstrip.png` | Reviewed selection, cursor movement, click and result frames. |

The edit trims automation waits. Three source ranges remain inspectable: 2.85–4.65, 6.35–8.65 and 10.35–13.65 seconds. The real pointer is captured; a native blue halo and pulse make its movement and middle-click easier to follow. Captions and framing are annotations, not fabricated app behavior.

Review covered fresh rendered frames across every cut and interaction, GIF frames, source/result Accessibility values and clipboard restoration. FFprobe confirms duration, dimensions, frame rate and the absence of audio. Playback at normal speed has not received a separate human review.

## Edit again

Use [Tesseract 0.3.1](https://github.com/mirage-hq/Tesseract/releases/tag/v0.3.1), locally. Work inside `Explainer/`; temporary JSON belongs to ignored `.tesseract-work/`.

1. Check out `Primary-Paste.tsrct` to `.tesseract-work/real-demo.json`.
2. Run `python3 author.py .tesseract-work/real-demo.json .tesseract-work/final.json`.
3. Commit that JSON into the portable project; render and inspect fresh filmstrip/hero frames.
4. Export MP4 at `--resolution 1080p --fps 30`; encode its 960-pixel, 15-fps GIF derivative.

For a new recording, the guest-only `Scripts/qa_capture.swift` uses existing guest Screen Recording approval. It refuses the physical host. Capture named fixture windows; keep raw guest recordings outside Git. No host viewer is needed.

[Rights inventory](Rights.md). Original edit, fixtures and overlays are GPL-3.0-only; incidental Apple UI retains its owner's rights. Figtree's separate SIL OFL is included in `Explainer/FONT-LICENSE.txt`.
