# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Makes the + picker's sprite sheet (TP-17; steward decision, 2026-10-31): every picker emoji
# in one WebP, in the picker's order, and priv/emoji/sprite.json describing it. Run it after
# any change to the emoji or the server's reactions, then recompile:
#
#     mix run --no-start priv/emoji/sprite.exs

alias Vix.Vips.{Image, Operation}

{:ok, _} = Application.ensure_all_started(:vix)

# 36 px cells: shown at 22 px, sharp enough on dense screens, about 0.8 MB.
size = 36
columns = 40
images = Idejo.Emoji.picker_images()

tiles =
  for {name, path} <- images do
    file = Path.join("priv/static", path)
    {:ok, tile} = Operation.thumbnail(file, size, height: size)

    {:ok, tile} =
      if Image.has_alpha?(tile), do: {:ok, tile}, else: Operation.bandjoin_const(tile, [255.0])

    case Operation.gravity(tile, :VIPS_COMPASS_DIRECTION_CENTRE, size, size,
           extend: :VIPS_EXTEND_BACKGROUND,
           background: [0.0, 0.0, 0.0, 0.0]
         ) do
      {:ok, tile} -> tile
      {:error, reason} -> raise "#{name}: #{reason}"
    end
  end

{:ok, sheet} = Operation.arrayjoin(tiles, across: columns)
:ok = Operation.webpsave(sheet, "priv/static/emoji/sprite.webp", Q: 70, keep: [])

File.write!(
  "priv/emoji/sprite.json",
  Jason.encode!(
    %{
      version: Idejo.Emoji.version(),
      columns: columns,
      rows: div(length(images) + columns - 1, columns),
      names: Enum.map(images, &elem(&1, 0))
    },
    pretty: true
  ) <> "\n"
)

IO.puts("#{length(images)} emoji, #{File.stat!("priv/static/emoji/sprite.webp").size} bytes")
