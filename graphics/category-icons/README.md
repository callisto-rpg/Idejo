# Category icons

The 63 icons a category may take (RP-03), in three sets: Topics, Sports and More. They are
the steward's, © Mariano Pictet, licensed under
[CC-BY-4.0](../../LICENSES/CC-BY-4.0.txt) (steward decision, 2026-11-15): reuse them,
change them, credit "Mariano Pictet".

idejo reads these files when it compiles (`Idejo.Forum.CategoryIcons`) and draws them as
SVG elements on a tile of the category's colour. To edit an icon, keep to these rules, or
it will not draw:

- A 32 × 32 canvas (`viewBox="0 0 32 32"`).
- The **tile first**: a `rect` of the full canvas whose `rx` gives the corner (idejo sets
  its own).
- **Two colours only**, as `fill` or `stroke` attributes (no `style`, no CSS classes):
  `#6567e7` is the tile's colour (the category's, at its place; used on shapes, it cuts
  them out of the white ones), `#ffffff` the shapes' (white or near-black on the web,
  whichever reads better on the category's colour). `none` is allowed.
- Only `rect`, `circle`, `ellipse`, `path` and `g` (with `transform` if needed); anything
  else is left out. No text, images, gradients, masks or filters.

An editor such as Inkscape may add metadata or `style` attributes: save as plain SVG, then
check that the colours are attributes. A new icon also needs its id in the module's
`@sets` and a name in `IdejoWeb.CategoryIconNames`.
