# Board references

Reference images of the current mobile design, one per board, locale and theme.
`manifest.json` is the source of truth: for every reference it records the design
board key, the Pen node id, the export it was derived from with that export's
SHA-256, the reference's own SHA-256, and the SHA-256 of the design file the
exports were taken from.

- References are 1x (393x852 px for a 393x852 pt board), derived from the 2x
  exports by a 2x2 box average in premultiplied RGBA. Board corners stay
  transparent and are not compared.
- `board` is the capture board the reference is compared with; `key` is the
  design board. A dark proof (MOB-DK01, MOB-DK03) is the dark reference of its
  screen.
- `expected-deviations.json` lists the reviewed, known differences between the
  app and these references. See `docs/board-verification.md`.

Check the references (CI runs this):

```sh
python3 scripts/design-references.py --check
```

Detect stale references against a newer export set, and re-derive them:

```sh
python3 scripts/design-references.py --check --boards <exports-dir> --design-file <design.pen>
python3 scripts/design-references.py --update --boards <exports-dir> --design-file <design.pen>
```

Never edit a reference image by hand.
