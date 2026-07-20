# notion-transcribe

macOS menu-bar app: point it at a folder of interview footage, get transcripts
in Notion. Shoot in the afternoon, script at night, edit in the morning.

- Extracts audio from anything QuickTime plays (Sony XAVC-S, MOV, MXF, BRAW
  via proxies, field-recorder WAVs) using AVFoundation
- Transcribes with **whisperx** (large-v3-turbo + wav2vec2 forced alignment —
  word-accurate timecodes that survive the trip into an NLE), falling back to
  whisper.cpp automatically
- Posts one Notion page per clip: timestamped paragraphs, related to the
  right project by parsing `yy.mm_Project_JobCode` folder names (fuzzy title
  matching tolerates drift), tagged for filtering
- **B-roll gate**: clips under a configurable minimum duration (default 60s)
  are skipped — interviews are long takes, b-roll is short bursts
- Idempotent: re-running a folder never duplicates
- Headless mode for automation: `NotionTranscribe --transcribe /path/to/folder`
  (the companion [DIT Media Ingest](https://github.com/1calledluke/notion-offload)
  app triggers this automatically after verified card dumps)

## Requirements

- macOS 14+, `brew install whisper-cpp`, a whisper model in `~/Models/`
- whisperx in `~/venvs/whisperx` for aligned timecodes (optional; falls back)
- A Notion integration token (Settings…)

## Build

```bash
swift build && ./build.sh install
./.build/debug/NotionTranscribe --selftest
```

---

Built by [Index Video Production](https://indexvideoproduction.com) with Claude Code.
