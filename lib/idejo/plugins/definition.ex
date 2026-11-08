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
        "block": "video",                  // "video", "iframe", "button" or "card"
        "video": {                         // only for "video"
          "match": ["^https://youtu\\.be/(?<id>[A-Za-z0-9_-]{11})"],
          "embed": "https://www.youtube-nocookie.com/embed/{id}"
        }
      }

  What each block asks for in its dialog: `video` a link (matched by one of `match`, whose
  `id` group fills `{id}` in `embed`, an https address); `iframe` a frame's code or address;
  `button` a label and a link; `card` a label and Markdown. `argument` fills the first of
  those: a `link` argument a video's link, a `text` one a button's or card's label.
  """

  use Gettext, backend: IdejoWeb.Gettext

  @blocks ~w(video iframe button card)
  @arguments ~w(link text none)
  @max_bytes 32_768

  @enforce_keys [:command, :name, :block, :argument]
  defstruct [:command, :name, :block, :argument, description: "", help: "", video: nil]

  @type t :: %__MODULE__{
          command: String.t(),
          name: String.t(),
          block: String.t(),
          argument: String.t(),
          description: String.t(),
          help: String.t(),
          video: %{match: [Regex.t()], embed: String.t(), origin: String.t()} | nil
        }

  @doc "The largest plugin file read, in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The blocks a plugin can draw."
  @spec blocks() :: [String.t()]
  def blocks, do: @blocks

  @doc """
  Reads a plugin file's text. `{:error, reason}`, a sentence for the admin page, when it is
  not a plugin Idejo can use.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, String.t()}
  def parse(text) when is_binary(text) and byte_size(text) > @max_bytes,
    do: {:error, gettext("The file is larger than %{kb} KB.", kb: div(@max_bytes, 1024))}

  def parse(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, %{} = json} -> from_json(json)
      {:ok, _other} -> {:error, gettext("The file is not a JSON object.")}
      {:error, _} -> {:error, gettext("The file is not valid JSON.")}
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
         {:ok, video} <- video(block, json["video"]) do
      {:ok,
       %__MODULE__{
         command: command,
         name: name,
         description: description,
         help: help,
         block: block,
         argument: argument,
         video: video
       }}
    end
  end

  defp version(1), do: :ok
  defp version(_), do: {:error, gettext("\"idejo_plugin\" must be 1.")}

  defp command(command) when is_binary(command) do
    if command =~ ~r/^[a-z0-9]+(-[a-z0-9]+)*$/ and String.length(command) <= 30,
      do: {:ok, command},
      else:
        {:error,
         gettext("\"command\" may only hold lower-case letters, digits and dashes, at most 30.")}
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
        {:error,
         gettext("\"%{field}\" is longer than %{max} characters.", field: field, max: max)}

      true ->
        {:ok, value}
    end
  end

  defp text(_value, field, _max, _required?),
    do: {:error, gettext("\"%{field}\" must be text.", field: field)}

  defp missing(field), do: {:error, gettext("\"%{field}\" is missing.", field: field)}

  defp one_of(value, allowed, field) do
    if value in allowed,
      do: {:ok, value},
      else:
        {:error,
         gettext("\"%{field}\" must be one of %{values}.",
           field: field,
           values: Enum.join(allowed, ", ")
         )}
  end

  defp argument_fits("video", argument) when argument in ~w(link none), do: :ok
  defp argument_fits("iframe", "none"), do: :ok

  defp argument_fits(block, argument) when block in ~w(button card) and argument in ~w(text none),
    do: :ok

  defp argument_fits(block, argument),
    do:
      {:error,
       gettext(~s|A "%{block}" plugin cannot take a "%{argument}" argument.|,
         block: block,
         argument: argument
       )}

  defp video("video", %{"match" => [_ | _] = patterns, "embed" => embed})
       when length(patterns) <= 10 and is_binary(embed) do
    with {:ok, regexes} <- patterns(patterns),
         {:ok, origin} <- embed_origin(embed) do
      {:ok, %{match: regexes, embed: embed, origin: origin}}
    end
  end

  defp video("video", _),
    do:
      {:error,
       gettext(~s|A "video" plugin needs "video" with "match" (1 to 10 patterns) and "embed".|)}

  defp video(_block, _), do: {:ok, nil}

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
      {:error, _} -> {:error, gettext(~s|A "match" pattern is not a valid regular expression.|)}
    end
  end

  defp pattern(_pattern),
    do: {:error, gettext(~s|Each "match" pattern must be text, at most 300 characters.|)}

  defp with_id(regex) do
    if "id" in Regex.names(regex),
      do: {:ok, regex},
      else: {:error, gettext(~s|Each "match" pattern needs a group named "id".|)}
  end

  # The embed address: https, a host, `{id}` in its path or query, nothing else to fill.
  defp embed_origin(embed) do
    uri = URI.parse(String.replace(embed, "{id}", "x"))

    if uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and String.contains?(embed, "{id}") and
         is_nil(uri.fragment) do
      {:ok, origin(uri)}
    else
      {:error, gettext("\"embed\" must be an https address holding {id}.")}
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
