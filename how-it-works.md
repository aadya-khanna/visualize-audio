Colors:!!
- signal energy depends on loudness/intensity of the audio 
- uses rolling window of last 40 samples for percentile calculation
- current color mapping:
    - low energy / dark timbre → mellow (deep blue/purple)
    - low energy / bright timbre → calm (teal)
    - high energy / dark timbre → aggressive (red/magenta)
    - high energy / bright timbre → energetic (warm orange)

Audio -> Visual :
- applies log-scaled frequency bucketing to convert data into visual bars (~96 bars)
- motion blur and attack/delay easing applied onto bar movement

This pipeline (and the color mapping above) is implemented twice, kept in algorithmic sync:
- **Web app** (`src/`): Essentia.js over a Web Audio Analyser node, mic/loopback-device capture,
  Spotify via OAuth.
- **macOS app** (`macos/`): native Swift reimplementation of the same math (vDSP FFT +
  hand-written energy/centroid/loudness, see `macos/Sources/VisualizeAudio/Audio/`), system-wide
  Core Audio process tap instead of a loopback device, Spotify via the private `MediaRemote`
  framework instead of OAuth.