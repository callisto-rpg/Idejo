# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Forum.CategoryIcons do
  @moduledoc """
  The icons a category may take (RP-03; steward decision, 2026-10-23): the steward's three
  sets, Topics, Sports and More, drawn on a 32 px grid as a tile in the category's colour with
  the shapes cut out in white or black, whichever reads better on it.

  The drawings are `graphics/category-icons/<id>.svg` (CC-BY-4.0, steward decision,
  2026-11-15), read when this module compiles: a tile first, in `#6567e7`, the shapes in
  `#6567e7` (cut out) or `#ffffff`. Those two colours and the tile's corner become three
  placeholders, `{{bg}}`, `{{fg}}` and `{{rx}}`. The files are parsed into a tree, so they are
  drawn as elements, never as raw HTML; `shapes/2` fills the placeholders in.
  """

  # Each set's icons, in the order the admin's picker shows them.
  @sets [
    topics: ~w(games sports live cinema music plants animals books food travel art science news
               photo tech learning),
    sports: ~w(soccer football rugby tennis basketball baseball volleyball hockey golf
               tabletennis swimming cycling running skiing boxing motorsport),
    more: ~w(general qa announce intro feedback events showcase market health fashion diy
             parenting relationships cars pets finance careers history philosophy languages
             politics tv comics writing crafts boardgames podcasts nature space environment
             weather)
  ]

  @dir Path.expand("../../../graphics/category-icons", __DIR__)

  @icons for {group, ids} <- @sets, id <- ids, do: {id, group}

  for {id, _group} <- @icons, do: @external_resource(Path.join(@dir, id <> ".svg"))

  @typedoc "An SVG element: its tag, its attributes and its children."
  @type shape :: {String.t(), [{atom(), String.t()}], [shape()]}

  @shape_tags ~w(rect circle ellipse path g)

  # The drawing's colours and the tile's corner (its first rx) into placeholders.
  mark = fn svg ->
    svg
    |> String.replace(~r/"#6567e7"/i, ~S("{{bg}}"))
    |> String.replace(~r/"#ffffff"/i, ~S("{{fg}}"))
    |> String.replace(~r/rx="[^"]*"/, ~S(rx="{{rx}}"), global: false)
  end

  # "<g fill=..><rect .../></g>" into [{"g", [fill: ..], [{"rect", [...], []}]}].
  shape_tags = @shape_tags

  parse = fn markup ->
    # Only the shapes this module draws; any other element is left out.
    tokens =
      ~r{<(/?)(\w+)([^>]*?)(/?)>}
      |> Regex.scan(markup, capture: :all_but_first)
      |> Enum.filter(fn [_, tag, _, _] -> tag in shape_tags end)

    attributes = fn attrs ->
      for [name, value] <- Regex.scan(~r/([\w-]+)="([^"]*)"/, attrs, capture: :all_but_first),
          do: {String.to_atom(name), value}
    end

    {[tree], []} =
      Enum.reduce(tokens, {[[]], []}, fn
        ["", tag, attrs, "/"], {[siblings | stack], open} ->
          {[[{tag, attributes.(attrs), []} | siblings] | stack], open}

        ["", tag, attrs, ""], {stack, open} ->
          {[[] | stack], [{tag, attributes.(attrs)} | open]}

        ["/", tag, _, _], {[children, siblings | stack], [{tag, attrs} | open]} ->
          {[[{tag, attrs, Enum.reverse(children)} | siblings] | stack], open}
      end)

    Enum.reverse(tree)
  end

  parsed =
    for {id, _group} <- @icons, into: %{} do
      svg = File.read!(Path.join(@dir, id <> ".svg"))
      {id, parse.(mark.(svg))}
    end

  @parsed parsed

  @ids Enum.map(@icons, &elem(&1, 0))

  # The eight tints a category without a colour of its own gets from its id.
  @tints ~w(#6567e7 #008ec8 #009690 #0fa05c #ce9200 #dc631e #dd3858 #b740b1)

  @doc "Every icon id, in order."
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc "The icon ids of each set, in order: `[{:topics, ids}, {:sports, ids}, {:more, ids}]`."
  @spec groups() :: [{atom(), [String.t()]}]
  def groups, do: @sets

  @doc "Returns true when `id` names an icon."
  @spec icon?(term()) :: boolean()
  def icon?(id), do: id in @ids

  @doc "The tint of a category without a colour of its own, from its id: `#rrggbb`."
  @spec tint(Ecto.UUID.t()) :: String.t()
  def tint(id), do: Enum.at(@tints, :erlang.phash2(id, length(@tints)))

  @doc """
  The colour for shapes drawn on `colour` (`#rrggbb`): white or near-black, whichever has the
  higher WCAG contrast ratio with it.
  """
  @spec contrast(String.t()) :: String.t()
  def contrast("#" <> hex) do
    [r, g, b] =
      for <<pair::binary-size(2) <- hex>> do
        c = String.to_integer(pair, 16) / 255
        if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end

    luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # #111111 has a relative luminance of about 0.0056.
    on_white = 1.05 / (luminance + 0.05)
    on_black = (luminance + 0.05) / 0.0556
    if on_black > on_white, do: "#111111", else: "#ffffff"
  end

  @doc """
  The shapes of icon `id` on a tile of `colour` (a checked `#rrggbb`), or nil: elements to draw
  inside an `<svg viewBox="0 0 32 32">`.
  """
  @spec shapes(String.t(), String.t()) :: [shape()] | nil
  def shapes(id, "#" <> _ = colour) do
    case Map.fetch(@parsed, id) do
      {:ok, tree} ->
        fill(tree, %{"{{bg}}" => colour, "{{fg}}" => contrast(colour), "{{rx}}" => "7"})

      :error ->
        nil
    end
  end

  defp fill(tree, values) do
    for {tag, attrs, children} <- tree do
      {tag, for({name, value} <- attrs, do: {name, Map.get(values, value, value)}),
       fill(children, values)}
    end
  end
end
