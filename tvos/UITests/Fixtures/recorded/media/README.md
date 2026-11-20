# Synthetic playback fixture

These files are generated test media, not copied broadcaster content. The picture is a blue frame with a yellow rectangle and a 440 Hz tone. Duration: 900 seconds, enough for the existing remote-navigation and background-playback checks. Tests still use the actual AVPlayer, picture layer, frame decoder, controls, and lifecycle.

Regenerate with ffmpeg:

```sh
ffmpeg -f lavfi -i 'color=c=0x347fc4:s=320x180:r=6' -f lavfi -i 'sine=frequency=440:sample_rate=22050' -t 900 -vf 'drawbox=x=80:y=40:w=160:h=100:color=yellow:t=fill' -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -c:a aac -b:a 16k -movflags +faststart picture.mp4
ffmpeg -i picture.mp4 -vn -c:a copy sound.m4a
```

The DEBUG-only `-kjfixturemedia YES` switch requires an explicit `-kjfixtures` directory. Missing media fails the request; it does not silently use a live stream. Omit the media switch for live-carrier integration probes. Release builds contain no fixture interception.

Recorded receiver/chat JSON is reused from PR #66, without its changed assertions or dead-stream skips.
