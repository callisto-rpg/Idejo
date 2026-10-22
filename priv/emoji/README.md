# Emoji data (TP-17)

- `emoji.json`: every emoji with a GitHub/Slack name, from
  [gemoji](https://github.com/wooorm/gemoji) 8.1.0 (MIT, © Titus Wormer): the emoji, its
  names (`:joy:`), its category, and the file name of its Twemoji image.
- `../static/emoji/*.svg`: those emoji's images from
  [Twemoji](https://github.com/jdecked/twemoji) 17.0.3 (graphics CC-BY-4.0, © Twitter and
  Jason Sofonia & Justine De Caires), served by the app itself (SP-04: no CDN).
- `../static/reactions/*.png`: the server's own reactions (`:agree:`, `:bruh:`…), CC-BY-4.0,
  © Mariano Pictet.

To update: download the npm tarball of `gemoji` and the Twemoji repository at a release tag,
then run `python3 -I priv/emoji/build.py <gemoji>/index.js <twemoji>/assets/svg
priv/emoji/emoji.json` and copy each entry's `file`.svg into `priv/static/emoji/` (replacing
the folder). Credits are in `NOTICE` and `REUSE.toml`.
