# Claude Replicant artwork

`app-icon.png` is the 1024 × 1024 icon master. Its warm/cool portraits use
the two-face *Replicant* reference supplied for this project. The cropped
portrait source is `replicant-portraits.png`.

Regenerate the committed Xcode sizes with:

```sh
python3 scripts/generate-icons.py
```

Requires Python 3 and Pillow. `--check` verifies the generated pixels without
writing files. The app build uses the committed assets and does not require
Pillow.
