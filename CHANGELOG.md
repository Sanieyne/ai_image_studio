# Changelog

## v0.3.0 (8 Oct 2026)

### Cloud GPUs
- Prices match Vast.ai: storage is priced per GB per month (it was charged about
  24x too much) and only for the size you choose; the offer card, side panel,
  Rent buttons, confirmation dialog and billing show the same total.
- Bandwidth shown per GB for download and upload.
- Renting shows real progress (host status, engine starting, model download %),
  elapsed time and credits so far; Stop instance from the progress screen or the
  new "Your active GPUs" list. Failures say why and what was charged or refunded.
- Only GPUs the engine supports are offered (RTX 20-series / GTX 16-series and newer).
- While rentals are paused, offers and prices stay browsable with Rent disabled.

### Local engine
- Voice tab: Chatterbox English and Multilingual download and run locally;
  Breeze TTS 2 is marked "Cloud only".
- Models load only from the app's download folder.
- Top bar: "Engine starting…" / "Engine failed: <reason>", with Open engine log
  and Restart engine; a slow first start is no longer killed after 30 s.
- Engine built on PyTorch 2.11 (CUDA 12.8): RTX 20 to RTX 50 series.

### Downloads
- Resume after dropped connections and app restarts, retry with "Waiting for
  network…", pause / resume / cancel, refreshed expired links, real free-space check.

### Interface
- Sidebar tabs: all seven visible with readable labels, hover, focus and selected states.
- The prompt composer always matches the selected tab.
- Honest status labels and download-time estimates; the real app version in Settings.

### Accounts and security
- Sign-in on several devices at once; Sign Out ends this device's session.
- Many security and billing fixes on the server (see docs/DEPLOY_NOTES.md).
