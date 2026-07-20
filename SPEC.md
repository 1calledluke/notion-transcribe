# notion-transcribe — overnight interview transcription to Notion

New Swift Package macOS menu-bar app at `~/notion-transcribe`. Model after
`~/dit-ingest-app` (same structure: Package.swift, Sources/NotionTranscribe/,
build.sh producing "Notion Transcribe.app", LSUIElement accessory app,
ad-hoc codesign). Swift 5.9+, macOS 14+. No third-party dependencies.

## Purpose
Luke picks a folder of interview footage (or drops one on the menu). The app
extracts audio from every media file, transcribes each with whisper-cli, and
posts one Notion page per clip into the Documents database, related to the
right Project. He scripts at night from the transcripts, edits in the morning.

## Config (~/Library/Application Support/NotionTranscribe/config.json)
```swift
struct Config: Codable {
    var notionToken: String = ""          // Settings window, like DIT app
    var documentsDB: String = "240714d3-333f-80ae-b147-e1bc122f0c86"
    var projectsDB: String = "232714d3-333f-80c8-88fd-d1eefeed3b3f"
    var whisperModel: String = NSHomeDirectory() + "/Models/ggml-large-v3-turbo.bin"
    var lastFolder: String = ""
}
```
On first launch, if notionToken is empty, try to copy it from
`~/Library/Application Support/DITIngest/config.json` (key `notionToken`) and
save. Settings window (menu → Settings…): token SecureField with show/hide +
Save, same pattern as DIT app's SettingsWindow.swift.

## Menu bar
Icon: `text.bubble` SF symbol. Menu:
- status line (disabled item): "Idle" / "Transcribing C0012.mov (3 of 9)…"
- "Transcribe Folder…" → NSOpenPanel (directories), starts a job
- "Settings…"
- "Quit"

## Pipeline (per job, run on a detached task, sequential per file)
1. Enumerate media files in the chosen folder recursively:
   video mp4/mov/m4v/mxf/mts/m2ts, audio wav/aif/aiff/mp3/m4a/flac.
   For `.braw`: look for `Proxy/<same-basename>.mp4|.mov` under the SAME folder
   tree and use that instead; if no proxy exists, SKIP the braw and log it.
   Skip files starting with "._", skip anything under /THMBNL/.
2. Audio extract: `/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 <src> <tmp.wav>`
   (16kHz mono LE16 wav). On afconvert failure log + skip file.
3. Transcribe: `whisper-cli -m <model> -f <tmp.wav> -osrt -of <tmpbase> -l en`
   (binary at /opt/homebrew/bin/whisper-cli). Parse the resulting .srt.
4. Post to Notion (api.notion.com, Notion-Version 2022-06-28):
   - Resolve the Project relation ONCE per job: walk UP from the chosen folder
     path looking for a component matching `yy.mm_ProjectName_JobCode` or
     `yy.mm_ProjectName` (regex `^\d{2}\.\d{2}_(.+?)(_\d+)?$`); extract
     ProjectName, query projectsDB for a page whose title equals it
     (POST /v1/databases/{id}/query with title filter). If no match, create the
     pages WITHOUT a Project relation and note it in the page body.
   - Create page in documentsDB: Name = "<clip filename> — Transcript",
     Tags = ["Transcript", "Auto"], Project relation when resolved.
   - Page body: an H2 "Transcript — <clip filename>", then the transcript as
     paragraph blocks. Group consecutive SRT cues into paragraphs of ≤1800
     chars, each paragraph prefixed with its starting timestamp like
     `[00:04:12]` (strip milliseconds). Notion caps 100 blocks per request:
     create the page with the first ≤90 blocks, then PATCH
     /v1/blocks/{page_id}/children for the rest in ≤90-block batches.
5. Log everything to ~/Library/Application Support/NotionTranscribe/app.log
   with timestamps (copy the tiny Logger from the DIT app).
6. When the job ends, post a macOS notification: "Transcribed 9 clips → Notion
   (2 skipped)". Menu status returns to Idle.

## Crash/duplicate safety
Before creating a page, query documentsDB for an existing page with the exact
same Name; if found, skip the clip (log "already transcribed"). This makes
re-running a folder idempotent.

## Build & verify
- `swift build` clean, then `./build.sh` (copy DIT app's build.sh shape;
  EXEC_NAME NotionTranscribe, APP_NAME "Notion Transcribe",
  BUNDLE_ID com.indexvideo.notiontranscribe).
- `--selftest` CLI flag: unit-test the SRT parser (feed a hardcoded SRT
  string; assert paragraph grouping + timestamp prefixes) and the project-name
  regex on: "26.07_Equip Videos_0118" → "Equip Videos";
  "25.12_Christmas" → "Christmas"; "Video" → no match. Print PASS lines, exit 0.
- Do NOT hardcode any tokens. Do not touch any other project on disk.
