# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Plugins do
  @moduledoc """
  Plugins (steward request, 2026-11-08): composer commands defined by JSON files
  (`Idejo.Plugins.Definition`), one file each, all in one folder (`dir/0`,
  `IDEJO_PLUGINS_DIR`, by default `plugins/` in the uploads folder, so it lives on the
  uploads volume; backups and uploads leave folders alone). Deleting a plugin's file removes it:
  its command leaves the composer and what it added under messages stops showing.

  Each is off until an administrator turns it on in **Admin → Plugins**, and then usable by
  owners and administrators and by the roles chosen there (`plugin_settings`, by command).
  The plugins Idejo ships (`priv/plugins/`) are copied into the folder once (`seed/0`, at
  boot): one deleted stays deleted, as its settings row remains.

  A plugin is never code. Whatever a file says, Idejo draws one of four blocks itself, from
  checked data (`Idejo.Plugins.Embed`): a video from an https embed address, a sandboxed
  frame from an https address, a link button, a card of Markdown.
  """
  use Gettext, backend: IdejoWeb.Gettext

  import Ecto.Query

  require Logger

  alias Idejo.Access
  alias Idejo.Accounts.User
  alias Idejo.Audit
  alias Idejo.Federation
  alias Idejo.Forum
  alias Idejo.Forum.Topic
  alias Idejo.Messages
  alias Idejo.Messages.{Automessages, Body, Message}
  alias Idejo.Plugins.{Definition, Embed, Setting}
  alias Idejo.RateLimit
  alias Idejo.Repo

  @table __MODULE__
  @max_embeds 10
  @max_label 100
  @max_card 10_000
  @max_address 2000

  @type plugin :: %{definition: Definition.t(), role_ids: [Ecto.UUID.t()]}

  ## The folder

  @doc "The plugins folder."
  @spec dir() :: Path.t()
  def dir do
    Application.get_env(:idejo, :plugins_dir) ||
      Path.join(Application.fetch_env!(:idejo, :uploads_dir), "plugins")
  end

  @doc """
  Every `*.json` file in the folder, by file name, for the admin page: its definition or why
  it cannot be used (`error`), and its settings. Read from the disk at each call.
  """
  @spec list() :: [
          %{
            file: String.t(),
            definition: Definition.t() | nil,
            error: String.t() | nil,
            setting: Setting.t()
          }
        ]
  def list do
    case read_files() do
      [] -> []
      files -> rows(files)
    end
  end

  defp rows(files) do
    settings = settings(for {_file, {:ok, d}} <- files, do: d.command)
    reserved = reserved()

    {rows, _seen} =
      Enum.map_reduce(files, MapSet.new(), fn
        {file, {:ok, definition}}, seen ->
          setting = Map.get(settings, definition.command, %Setting{command: definition.command})

          {%{
             file: file,
             definition: definition,
             error: conflict(definition.command, reserved, seen),
             setting: setting
           }, MapSet.put(seen, definition.command)}

        {file, {:error, reason}}, seen ->
          {%{file: file, definition: nil, error: reason, setting: nil}, seen}
      end)

    rows
  end

  defp conflict(command, reserved, seen) do
    cond do
      command in reserved ->
        gettext("!%{command} is already a command of Idejo or an automessage.", command: command)

      MapSet.member?(seen, command) ->
        gettext("Another file already defines !%{command}.", command: command)

      true ->
        nil
    end
  end

  defp read_files do
    case File.ls(dir()) do
      {:ok, names} ->
        names
        |> Enum.filter(&(Path.extname(&1) == ".json" and not String.starts_with?(&1, ".")))
        |> Enum.sort()
        |> Enum.map(fn name -> {name, read_file(Path.join(dir(), name))} end)

      {:error, _} ->
        []
    end
  end

  # The path is a name listed in the plugins folder (`read_files/0`), never a request's.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 32_768 ->
        case File.read(path) do
          {:ok, text} -> Definition.parse(text)
          {:error, _} -> {:error, gettext("The file cannot be read.")}
        end

      {:ok, %{type: :regular}} ->
        {:error,
         gettext("The file is larger than %{kb} KB.", kb: div(Definition.max_bytes(), 1024))}

      _ ->
        {:error, gettext("Not a file.")}
    end
  end

  defp settings(commands) do
    Repo.all(from s in Setting, where: s.command in ^commands) |> Map.new(&{&1.command, &1})
  end

  # Commands a plugin can never take: Idejo's own and the automessages'.
  defp reserved do
    MapSet.new(Automessages.reserved() ++ Enum.map(Automessages.list(), & &1.command))
  end

  ## Active plugins, cached

  @doc """
  The plugins turned on whose file is there and usable, by command. Kept a few seconds
  (`:plugins_cache_ms`, 5 s; 0 in tests), so a file deleted or added shows that soon, and
  `reload/0` forgets it at once.
  """
  @spec active() :: %{String.t() => plugin()}
  def active do
    ttl = Application.get_env(:idejo, :plugins_cache_ms, 5000)
    now = System.monotonic_time(:millisecond)

    case lookup() do
      {value, at} when now - at < ttl ->
        value

      _ ->
        value = load_active()
        store(value, now)
        value
    end
  end

  @doc "Forgets the cached plugins: the next `active/0` reads the folder again."
  @spec reload() :: :ok
  def reload do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, :active)
    :ok
  end

  @doc "Makes the cache's table; once, at boot (`Idejo.Application`)."
  @spec init_cache() :: :ok
  def init_cache do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ok
  end

  defp lookup do
    case :ets.whereis(@table) do
      :undefined -> nil
      _ -> with [{:active, value, at}] <- :ets.lookup(@table, :active), do: {value, at}
    end
  end

  defp store(value, now) do
    if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {:active, value, now})
  end

  defp load_active do
    for %{definition: %Definition{} = d, error: nil, setting: %Setting{enabled: true} = s} <-
          list(),
        into: %{},
        do: {d.command, %{definition: d, role_ids: s.role_ids}}
  rescue
    # Before the migration ran, or with the database away: no plugins rather than no page.
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("Plugins not loaded: #{Exception.message(error)}")
      %{}
  end

  @doc """
  The active plugins `user` may use in `topic`, by command: where they may post, an owner or
  administrator any of them, others those allowing one of their roles.
  """
  @spec usable(User.t() | nil, Topic.t(), %{String.t() => plugin()} | nil) :: [Definition.t()]
  def usable(user, topic, plugins \\ nil)
  def usable(nil, _topic, _plugins), do: []

  def usable(%User{} = user, %Topic{} = topic, plugins) do
    plugins = plugins || active()

    if plugins == %{} or not Forum.can_post?(user, topic) do
      []
    else
      roles = Access.roles_of(user)
      admin? = Enum.any?(roles, &(&1.built_in and &1.name in ~w(owner administrator)))
      held = MapSet.new(roles, & &1.id)

      for {_command, %{definition: d, role_ids: ids}} <- Enum.sort(plugins),
          admin? or Enum.any?(ids, &MapSet.member?(held, &1)),
          do: d
    end
  end

  @doc """
  What the content security policy needs (`frame-src`) while plugins are on: the embed
  origins of video plugins, and `https:` while a frame plugin is on.
  """
  @spec frame_sources() :: [String.t()]
  def frame_sources do
    active()
    |> Map.values()
    |> Enum.flat_map(fn
      %{definition: %{block: "video", video: %{origin: origin}}} -> [origin]
      %{definition: %{block: "iframe"}} -> ["https:"]
      _ -> []
    end)
    |> Enum.uniq()
  end

  @doc """
  The embeds of a message that show now: those of active plugins. A deleted file or a
  plugin turned off hides what it added (the rows stay, and show again if it comes back).
  """
  @spec shown([Embed.t()] | Ecto.Association.NotLoaded.t(), %{String.t() => plugin()}) ::
          [Embed.t()]
  def shown(embeds, active) when is_list(embeds) do
    Enum.filter(embeds, fn embed ->
      case active[embed.plugin] do
        %{definition: %{block: block}} -> block == embed.block
        nil -> false
      end
    end)
  end

  def shown(_embeds, _active), do: []

  ## Settings

  @doc "Turns a plugin on or off, as `admin`; audited `plugin.enable` / `plugin.disable`."
  @spec set_enabled(User.t(), String.t(), boolean()) :: {:ok, Setting.t()} | {:error, term()}
  def set_enabled(%User{} = admin, command, enabled?) when is_boolean(enabled?) do
    change(admin, command, if(enabled?, do: "plugin.enable", else: "plugin.disable"), fn s ->
      %{enabled: enabled?, role_ids: s.role_ids}
    end)
  end

  @doc """
  Sets the roles that may use a plugin, as `admin` (owners and administrators always may);
  ids of roles that do not exist are dropped. Audited `plugin.roles`.
  """
  @spec set_roles(User.t(), String.t(), [String.t()]) :: {:ok, Setting.t()} | {:error, term()}
  def set_roles(%User{} = admin, command, role_ids) when is_list(role_ids) do
    ids = for id <- role_ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id
    known = Repo.all(from r in Access.Role, where: r.id in ^ids, select: r.id)

    change(admin, command, "plugin.roles", fn s ->
      %{enabled: s.enabled, role_ids: Enum.filter(ids, &(&1 in known)) |> Enum.uniq()}
    end)
  end

  defp change(admin, command, action, fun) do
    if Enum.any?(list(), &match?(%{definition: %{command: ^command}, error: nil}, &1)) do
      result = Repo.transact(fn -> save(admin, command, action, fun) end)
      reload()
      result
    else
      {:error, :not_found}
    end
  end

  defp save(admin, command, action, fun) do
    before = Repo.get(Setting, command) || %Setting{command: command}

    with {:ok, setting} <- upsert(command, fun.(before)),
         {:ok, _} <- Audit.record(admin, action, snapshot(before), snapshot(setting)) do
      {:ok, setting}
    end
  end

  defp upsert(command, %{enabled: enabled, role_ids: role_ids}) do
    now = DateTime.utc_now(:second)

    Repo.insert(
      %Setting{
        command: command,
        enabled: enabled,
        role_ids: role_ids,
        created_at: now,
        updated_at: now
      },
      on_conflict: [set: [enabled: enabled, role_ids: role_ids, updated_at: now]],
      conflict_target: :command,
      returning: true
    )
  end

  defp snapshot(%Setting{} = s),
    do: %{"command" => s.command, "enabled" => s.enabled, "role_ids" => s.role_ids}

  @doc """
  Installs an uploaded plugin, as `admin`: checked (`Definition.parse/1`), its command free,
  then written to the folder as `<command>.json`, off. Audited `plugin.install`.
  """
  @spec install(User.t(), binary()) ::
          {:ok, Definition.t()} | {:error, String.t()}
  def install(%User{} = admin, text) when is_binary(text) do
    path = fn d -> Path.join(dir(), d.command <> ".json") end

    with {:ok, definition} <- Definition.parse(text),
         :ok <- free(definition, path.(definition)),
         :ok <- write(path.(definition), text) do
      setting = %{enabled: false, role_ids: []}
      {:ok, _} = upsert(definition.command, setting)

      {:ok, _} =
        Audit.record(admin, "plugin.install", nil, %{
          "command" => definition.command,
          "name" => definition.name,
          "block" => definition.block
        })

      reload()
      {:ok, definition}
    end
  end

  defp free(definition, path) do
    cond do
      definition.command in reserved() ->
        {:error,
         gettext("!%{command} is already a command of Idejo or an automessage.",
           command: definition.command
         )}

      File.exists?(path) or
          Enum.any?(list(), &(&1.definition && &1.definition.command == definition.command)) ->
        {:error,
         gettext("A plugin for !%{command} is installed already. Delete its file first.",
           command: definition.command
         )}

      true ->
        :ok
    end
  end

  # The path is the plugins folder and a command checked by `Definition` ([a-z0-9-]).
  # sobelow_skip ["Traversal.FileModule"]
  defp write(path, text) do
    tmp = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, text),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Plugin not written: #{inspect(reason)}")
        {:error, gettext("The plugins folder cannot be written to.")}
    end
  end

  @doc """
  Copies the plugins Idejo ships (`priv/plugins/*.json`) into the folder, each once: never
  one that has a settings row already (installed before, then perhaps deleted on purpose).
  Run at boot; does nothing it cannot do.
  """
  @spec seed() :: :ok
  # The files are the release's own (`priv/plugins`).
  # sobelow_skip ["Traversal.FileModule"]
  def seed do
    source = Application.app_dir(:idejo, "priv/plugins")

    for name <- Path.wildcard(Path.join(source, "*.json")),
        text = File.read!(name),
        {:ok, definition} <- [Definition.parse(text)],
        not Repo.exists?(from s in Setting, where: s.command == ^definition.command) do
      target = Path.join(dir(), definition.command <> ".json")

      if File.exists?(target) or write(target, text) == :ok,
        do: upsert(definition.command, %{enabled: false, role_ids: []})
    end

    reload()
  rescue
    error ->
      Logger.warning("Bundled plugins not copied: #{Exception.message(error)}")
      :ok
  end

  ## Using a plugin

  @doc """
  Checks what the plugin's dialog (or its `!command:…:` argument) gave: `params` with
  `"link"` (a video's), `"code"` (a frame's code or address), `"label"`, `"url"` (a
  button's link) and `"body"` (a card's Markdown), as the block needs. Returns the block's
  data and the text a message of its own would hold.
  """
  @spec prepare(Definition.t(), map()) ::
          {:ok, map(), String.t()}
          | {:error, :link | :code | :label | :url | :body}
  def prepare(%Definition{block: "video", video: video}, params) do
    link = String.trim(params["link"] || "")

    with {:ok, id} <- video_id(video, link) do
      {:ok, %{"src" => String.replace(video.embed, "{id}", id), "link" => link}, link}
    end
  end

  def prepare(%Definition{block: "iframe"}, params) do
    with {:ok, src} <- frame_src(params["code"] || "") do
      {:ok, %{"src" => src}, src}
    end
  end

  def prepare(%Definition{block: "button"}, params) do
    with {:ok, label} <- label(params["label"]),
         {:ok, url} <- link(params["url"]) do
      {:ok, %{"label" => label, "url" => url}, label}
    end
  end

  def prepare(%Definition{block: "card"}, params) do
    body = String.trim(params["body"] || "")

    with {:ok, label} <- label(params["label"]),
         :ok <-
           if(body != "" and String.length(body) <= @max_card, do: :ok, else: {:error, :body}) do
      {:ok, %{"label" => label, "body_md" => body}, label}
    end
  end

  @doc "The largest card, in characters."
  @spec max_card() :: pos_integer()
  def max_card, do: @max_card

  @doc "The longest label of a button or card, in characters."
  @spec max_label() :: pos_integer()
  def max_label, do: @max_label

  defp video_id(video, link) do
    with true <- link != "" and String.length(link) <= @max_address,
         id when is_binary(id) <- Enum.find_value(video.match, &captured_id(&1, link)),
         true <- id =~ ~r/^[A-Za-z0-9_-]{1,64}$/ do
      {:ok, id}
    else
      _ -> {:error, :link}
    end
  end

  defp captured_id(regex, link) do
    case Regex.named_captures(regex, link) do
      %{"id" => id} -> id
      _ -> nil
    end
  end

  # A frame's pasted code (`<iframe src="…">`) or its bare address: only the address is kept,
  # https, never this server's own (a frame of it would leave the sandbox).
  defp frame_src(code) do
    code = String.trim(code)

    raw =
      case Regex.run(~r/<iframe\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')/i, code) do
        [_, double] -> double
        [_, "", single] -> single
        nil -> code
      end

    src = raw |> String.trim() |> unescape()

    if String.length(src) <= @max_address and https?(src) and not own_host?(src),
      do: {:ok, src},
      else: {:error, :code}
  end

  defp unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp https?(address) do
    uri = URI.parse(address)

    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
      not String.contains?(address, [" ", "\n", "\t", "\"", "<", ">"])
  end

  defp own_host?(address) do
    own = URI.parse(Application.fetch_env!(:idejo, :base_uri)).host
    host = URI.parse(address).host
    String.downcase(host) == String.downcase(own || "")
  end

  defp label(label) do
    label = String.trim(label || "")

    if label != "" and String.length(label) <= @max_label,
      do: {:ok, label},
      else: {:error, :label}
  end

  defp link(url) do
    url = String.trim(url || "")
    uri = URI.parse(url)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         String.length(url) <= @max_address and not String.contains?(url, [" ", "\"", "<", ">"]),
       do: {:ok, url},
       else: {:error, :url}
  end

  @doc """
  Adds what a plugin made under the author's own `message` (open or closed, not deleted),
  where they may post and may use the plugin; at most #{@max_embeds} per message. Broadcast
  as the message, after its transaction.
  """
  @spec attach(User.t(), Message.t(), String.t(), map()) ::
          {:ok, Message.t()}
          | {:error,
             :forbidden | :too_many | :rate_limited | :link | :code | :label | :url | :body}
  def attach(%User{} = user, %Message{} = message, command, params) do
    topic = Repo.get!(Topic, message.topic_id)

    with {:ok, definition} <- may_use(user, topic, command),
         :ok <- own(user, message),
         {:ok, data, _text} <- prepare(definition, params),
         :ok <- RateLimit.check(:commit, user.id),
         {:ok, _embed} <- Repo.transact(fn -> insert(user, message, topic, definition, data) end) do
      message = Repo.get!(Message, message.id)
      Messages.broadcast(message.topic_id, {:message, message})
      {:ok, message}
    end
  end

  @doc """
  A plugin's block with no message to go under: posts a closed message (its text the link or
  the label, so excerpts, search and notifications read something), then adds it. Checked
  before anything is posted. `reply_to_id` as for `Idejo.Forum.post_message/3`.
  """
  @spec post(User.t(), Topic.t(), String.t(), map(), Ecto.UUID.t() | nil) ::
          {:ok, Message.t()} | {:error, term()}
  def post(%User{} = user, %Topic{} = topic, command, params, reply_to_id \\ nil) do
    with {:ok, definition} <- may_use(user, topic, command),
         {:ok, _data, text} <- prepare(definition, params),
         {:ok, message} <-
           Forum.post_message(user, topic, %{"body" => text, "reply_to_id" => reply_to_id}) do
      attach(user, message, command, params)
    end
  end

  @doc "The plugin `command` when `user` may use it in `topic`."
  @spec may_use(User.t(), Topic.t(), String.t()) :: {:ok, Definition.t()} | {:error, :forbidden}
  def may_use(user, topic, command) do
    case Enum.find(usable(user, topic), &(&1.command == command)) do
      nil -> {:error, :forbidden}
      definition -> {:ok, definition}
    end
  end

  defp own(user, message) do
    cond do
      message.author_id != user.id or message.deleted_at != nil ->
        {:error, :forbidden}

      Repo.aggregate(from(e in Embed, where: e.message_id == ^message.id), :count) >= @max_embeds ->
        {:error, :too_many}

      true ->
        :ok
    end
  end

  defp insert(user, message, topic, definition, data) do
    data =
      if definition.block == "card",
        do: Map.put(data, "body_html", Body.to_html(data["body_md"], Body.context(message))),
        else: data

    with {:ok, embed} <-
           Repo.insert(%Embed{
             id: Federation.generate_id(),
             message_id: message.id,
             plugin: definition.command,
             block: definition.block,
             data: data
           }),
         {:ok, _activity} <-
           Repo.insert(
             Federation.activity_changeset(%{
               actor_uri: user.uri,
               verb: "update",
               object_uri: message.uri,
               target_uri: topic.uri,
               payload: %{"type" => "Note", "plugin" => definition.command}
             })
           ) do
      {:ok, embed}
    end
  end
end
