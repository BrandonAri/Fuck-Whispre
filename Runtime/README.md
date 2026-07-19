# Bundled local runtime

`Models/ggml-base.en.bin` is downloaded from the official `ggerganov/whisper.cpp` model repository by:

```bash
Vendor/whisper.cpp/models/download-ggml-model.sh base.en Runtime/Models
```

The build script packages this model together with a statically linked, Metal-enabled `whisper-cli` executable. No network connection is used during transcription.
