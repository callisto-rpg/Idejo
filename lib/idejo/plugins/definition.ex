# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins.Definition do
  @moduledoc """
  A plugin file, read and checked (steward request, 2026-11-08). A plugin is data, never code:
  one JSON object naming a composer command and one of the blocks Idejo itself draws, so an
  uploaded plugin can do nothing a built-in one cannot.

      {
        "idejo_plugin": 1,
        "command": "youtube",              // !youtube; lower-case letters, digits, "-"
        "name": "YouTube video",           // the dialog's title and the admin page's name
        "description": "…",                // one line, in the composer's ! list
        "help": "…",                       // optional, the Help page
        "argument": "link",                // "link", "text" or "none": what !command:…: carries
        "block": "video",                  // "video", "iframe", "button", "card",
                                           // "collapse" or "forum"
        "video": {                         // only for "video"
          "match": ["^https://youtu\\.be/(?<id>[A-Za-z0-9_-]{11})"],
          "embed": "https://www.youtube-nocookie.com/embed/{id}"
        }
      }

  What each block asks for in its dialog: `video` a link (matched by one of `match`, whose
  `id` group fills `{id}` in `embed`, an https address); `iframe` a frame's code or address;
  `button` a label and a link; `card` a label and Markdown. `argument` fills the first of
  those: a `link` argument a video's link, a `text` one a button's or card's label.

  Two more (steward request, 2026-11-09): `collapse` asks for nothing and draws nothing under
  the message: in the author's text, `!command title` followed by lines starting with `:`
  folds those lines under the title (`Idejo.Plugins.Folds`). `forum` searches a forums
  directory, `"directory": "https://…"` (its `GET /api/forums?q=` answers
  `{"forums": [{"name", "url", "logo", "join"}]}`; a `text` argument starts the search), and
  draws the chosen forum as a small card: logo, name, Join.
  """

  @blocks ~w(video iframe button card collapse forum)
  @arguments ~w(link text none)
  @max_bytes 32_768

  @enforce_keys [:command, :name, :block, :argument]
  defstruct [
    :command,
    :name,
    :block,
    :argument,
    description: "",
    help: "",
    video: nil,
    directory: nil
  ]

  @type t :: %__MODULE__{
          command: String.t(),
          name: String.t(),
          block: String.t(),
          argument: String.t(),
          description: String.t(),
          help: String.t(),
          video: %{match: [Regex.t()], embed: String.t(), origin: String.t()} | nil,
          directory: String.t() | nil
        }

  @doc "The largest plugin file read, in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The blocks a plugin can draw."
  @spec blocks() :: [String.t()]
  def blocks, do: @blocks

  @typedoc """
  Why a file is not a plugin Idejo can use (`parse/1`); the admin page words it
  (`IdejoWeb.PluginComponents.problem/1`).
  """
  @type problem ::
          {:too_large, kb :: pos_integer()}
          | :not_object
          | :not_json
          | :version
          | :command_format
          | {:missing, field :: String.t()}
          | {:too_long, field :: String.t(), max :: pos_integer()}
          | {:not_text, field :: String.t()}
          | {:not_one_of, field :: String.t(), [String.t()]}
          | {:argument, block :: String.t(), argument :: String.t()}
          | :video
          | :directory_https
          | :directory_missing
          | :pattern_invalid
          | :pattern_too_long
          | :pattern_no_id
          | :embed

  @doc """
  Reads a plugin file's text. `{:error, problem}` when it is not a plugin Idejo can use.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, problem()}
  def parse(text) when is_binary(text) and byte_size(text) > @max_bytes,
    do: {:error, {:too_large, div(@max_bytes, 1024)}}

  def parse(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, %{} = json} -> from_json(json)
      {:ok, _other} -> {:error, :not_object}
      {:error, _} -> {:error, :not_json}
    end
  end

  defp from_json(json) do
    with :ok <- version(json["idejo_plugin"]),
         {:ok, command} <- command(json["command"]),
         {:ok, name} <- text(json["name"], "name", 60, true),
         {:ok, description} <- text(json["description"], "description", 120, false),
         {:ok, help} <- text(json["help"], "help", 1000, false),
         {:ok, block} <- one_of(json["block"], @blocks, "block"),
         {:ok, argument} <- one_of(json["argument"] || "none", @arguments, "argument"),
         :ok <- argument_fits(block, argument),
         {:ok, video} <- video(block, json["video"]),
         {:ok, directory} <- directory(block, json["directory"]) do
      {:ok,
       %__MODULE__{
         command: command,
         name: name,
         description: description,
         help: help,
         block: block,
         argument: argument,
         video: video,
         directory: directory
       }}
    end
  end

  defp version(1), do: :ok
  defp version(_), do: {:error, :version}

  defp command(command) when is_binary(command) do
    if command =~ ~r/^[a-z0-9]+(-[a-z0-9]+)*$/ and String.length(command) <= 30,
      do: {:ok, command},
      else: {:error, :command_format}
  end

  defp command(_), do: missing("command")

  defp text(nil, field, _max, true), do: missing(field)
  defp text(nil, _field, _max, false), do: {:ok, ""}

  defp text(value, field, max, required?) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" and required? ->
        missing(field)

      String.length(value) > max ->
        {:error, {:too_long, field, max}}

      true ->
        {:ok, value}
    end
  end

  defp text(_value, field, _max, _required?),
    do: {:error, {:not_text, field}}

  defp missing(field), do: {:error, {:missing, field}}

  defp one_of(value, allowed, field) do
    if value in allowed,
      do: {:ok, value},
      else: {:error, {:not_one_of, field, allowed}}
  end

  defp argument_fits("video", argument) when argument in ~w(link none), do: :ok
  defp argument_fits(block, "none") when block in ~w(iframe collapse), do: :ok
  defp argument_fits("forum", argument) when argument in ~w(text none), do: :ok

  defp argument_fits(block, argument) when block in ~w(button card) and argument in ~w(text none),
    do: :ok

  defp argument_fits(block, argument), do: {:error, {:argument, block, argument}}

  defp video("video", %{"match" => [_ | _] = patterns, "embed" => embed})
       when length(patterns) <= 10 and is_binary(embed) do
    with {:ok, regexes} <- patterns(patterns),
         {:ok, origin} <- embed_origin(embed) do
      {:ok, %{match: regexes, embed: embed, origin: origin}}
    end
  end

  defp video("video", _), do: {:error, :video}

  defp video(_block, _), do: {:ok, nil}

  # A forums directory: an https address, no query or fragment (`/api/forums` is added).
  defp directory("forum", directory) when is_binary(directory) do
    uri = URI.parse(directory)

    if uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
         is_nil(uri.query) and is_nil(uri.fragment),
       do: {:ok, String.trim_trailing(directory, "/")},
       else: {:error, :directory_https}
  end

  defp directory("forum", _), do: {:error, :directory_missing}

  defp directory(_block, _), do: {:ok, nil}

  defp patterns(patterns) do
    Enum.reduce_while(patterns, {:ok, []}, fn pattern, {:ok, acc} ->
      case pattern(pattern) do
        {:ok, regex} -> {:cont, {:ok, acc ++ [regex]}}
        error -> {:halt, error}
      end
    end)
  end

  defp pattern(pattern) when is_binary(pattern) and byte_size(pattern) <= 300 do
    case Regex.compile(pattern) do
      {:ok, regex} -> with_id(regex)
      {:error, _} -> {:error, :pattern_invalid}
    end
  end

  defp pattern(_pattern), do: {:error, :pattern_too_long}

  defp with_id(regex) do
    if "id" in Regex.names(regex),
      do: {:ok, regex},
      else: {:error, :pattern_no_id}
  end

  # The embed address: https, a host, `{id}` in its path or query, nothing else to fill.
  defp embed_origin(embed) do
    uri = URI.parse(String.replace(embed, "{id}", "x"))

    if uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and String.contains?(embed, "{id}") and
         is_nil(uri.fragment) do
      {:ok, origin(uri)}
    else
      {:error, :embed}
    end
  end

  @doc "`https://host[:port]` of a parsed address."
  @spec origin(URI.t()) :: String.t()
  def origin(%URI{scheme: scheme, host: host, port: port}) do
    if port == URI.default_port(scheme),
      do: "#{scheme}://#{host}",
      else: "#{scheme}://#{host}:#{port}"
  end
end
