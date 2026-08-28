Colors:
- signal energy depends on loudness/intensity of the audio 
- uses rolling window of last 40 samples for percentile calculation
- current color mapping:
    - low energy / dark timbre → mellow (deep blue/purple)
    - low energy / bright timbre → calm (teal)
    - high energy / dark timbre → aggressive (red/magenta)
    - high energy / bright timbre → energetic (warm orange)

Audio -> Visual :
- uses Essentia api to convert audio input to raw data (Web Audio Analyser node)
- applies log-scaled frequency bucketing to convert data into visual bars (~96 bars)
- motion blur and attack/delay easing applied onto bar movement