# Optional Themearr audio processing

Themearr’s opt-in audio processing requires `ffmpeg` and `ffprobe`. Ordinary downloads keep their original audio and do not need these tools. Installing or updating Themearr does not enable processing or alter existing files.

To use processing, open a shell **inside the Themearr LXC**, then install the Debian package:

```bash
apt-get update
apt-get install ffmpeg
ffmpeg -version
ffprobe -version
```

Enable processing explicitly in Themearr Settings after both version checks succeed. System health reports missing tools when processing is enabled. Trimming also affects full-length background playback for other players sharing the media folders. Existing themes require a separate repair preview before any change.

A regular Themearr update preserves these packages and settings. The installer and updater report whether the tools are present; they leave package installation to the operator.

Companion application work: [Themearr/themearr#49](https://github.com/Themearr/themearr/issues/49).
