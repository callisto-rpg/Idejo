# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Load test (NF-01, NF-04): people sign in, open topics in their browser's way (the topic
# page, then its LiveView over a websocket), and some of them write as in a chat, pressing
# Enter every few seconds. Every commit carries a marker; the time until each other viewer of
# the topic receives it is the live latency (NF-01). See docs/load-testing.md.
#
#   mix run --no-start load/run.exs [--url http://localhost:4000] [--users 200]
#     [--topics 10] [--writers 30] [--duration 180] [--hot]
#
# --hot puts every viewer in one topic (the worst case for one broadcast). Users come from
# load/seed.exs: load0001@example.org … with the password "load test passphrase".

defmodule Load.WebSocket do
  @moduledoc """
  A minimal websocket client (RFC 6455) over plain TCP: enough for the LiveView socket of a
  local server. The process that connects receives `{:ws, pid, text}` for each text message.
  """
  use GenServer

  def start_link(owner, uri, headers), do: GenServer.start_link(__MODULE__, {owner, uri, headers})

  def send_text(pid, text), do: GenServer.cast(pid, {:send, text})

  @impl true
  def init({owner, %URI{} = uri, headers}) do
    {:ok, socket} =
      :gen_tcp.connect(String.to_charlist(uri.host), uri.port, [:binary, active: false], 10_000)

    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request =
      [
        "GET #{uri.path}?#{uri.query} HTTP/1.1\r\n",
        "Host: #{uri.host}:#{uri.port}\r\n",
        "Upgrade: websocket\r\nConnection: Upgrade\r\n",
        "Sec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n",
        Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
        "\r\n"
      ]

    :ok = :gen_tcp.send(socket, request)
    {:ok, rest} = read_handshake(socket, "")
    :ok = :inet.setopts(socket, active: true)
    state = %{socket: socket, owner: owner, buffer: "", fragments: []}
    {:ok, parse(state, rest)}
  end

  defp read_handshake(socket, acc) do
    {:ok, data} = :gen_tcp.recv(socket, 0, 10_000)
    acc = acc <> data

    case String.split(acc, "\r\n\r\n", parts: 2) do
      [head, rest] ->
        if head =~ ~r/\AHTTP\/1\.1 101/, do: {:ok, rest}, else: raise("handshake: #{head}")

      [_] ->
        read_handshake(socket, acc)
    end
  end

  @impl true
  def handle_cast({:send, text}, state) do
    :ok = :gen_tcp.send(state.socket, frame(0x1, text))
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state), do: {:noreply, parse(state, data)}
  def handle_info({:tcp_closed, _socket}, state), do: {:stop, :closed, state}

  # Client frames are masked (RFC 6455 §5.3).
  defp frame(opcode, payload) do
    mask = :crypto.strong_rand_bytes(4)
    size = byte_size(payload)

    length =
      cond do
        size < 126 -> <<1::1, size::7>>
        size < 65_536 -> <<1::1, 126::7, size::16>>
        true -> <<1::1, 127::7, size::64>>
      end

    [<<1::1, 0::3, opcode::4>>, length, mask, mask(payload, mask)]
  end

  defp mask(payload, <<a, b, c, d>>) do
    for {byte, i} <- Enum.with_index(:binary.bin_to_list(payload)), into: <<>> do
      <<Bitwise.bxor(byte, Enum.at([a, b, c, d], rem(i, 4)))>>
    end
  end

  defp parse(state, data) do
    buffer = state.buffer <> data

    case split_frame(buffer) do
      {:ok, fin, opcode, payload, rest} ->
        state |> handle_frame(fin, opcode, payload) |> Map.put(:buffer, "") |> parse(rest)

      :more ->
        %{state | buffer: buffer}
    end
  end

  defp split_frame(<<fin::1, _::3, opcode::4, 0::1, 127::7, size::64, rest::binary>>),
    do: take(fin, opcode, size, rest)

  defp split_frame(<<fin::1, _::3, opcode::4, 0::1, 126::7, size::16, rest::binary>>),
    do: take(fin, opcode, size, rest)

  defp split_frame(<<fin::1, _::3, opcode::4, 0::1, size::7, rest::binary>>) when size < 126,
    do: take(fin, opcode, size, rest)

  defp split_frame(_), do: :more

  defp take(fin, opcode, size, rest) do
    case rest do
      <<payload::binary-size(^size), rest::binary>> -> {:ok, fin, opcode, payload, rest}
      _ -> :more
    end
  end

  # Text (1), continuation (0), ping (9); closing (8) stops the client.
  defp handle_frame(state, 1, 0x1, payload), do: deliver(state, payload)
  defp handle_frame(state, 0, 0x1, payload), do: %{state | fragments: [payload]}
  defp handle_frame(state, 0, 0x0, payload), do: %{state | fragments: [payload | state.fragments]}

  defp handle_frame(state, 1, 0x0, payload),
    do:
      deliver(
        %{state | fragments: []},
        IO.iodata_to_binary(Enum.reverse([payload | state.fragments]))
      )

  defp handle_frame(state, _fin, 0x9, payload) do
    :ok = :gen_tcp.send(state.socket, frame(0xA, payload))
    state
  end

  defp handle_frame(_state, _fin, 0x8, _payload), do: exit(:closed)
  defp handle_frame(state, _fin, _opcode, _payload), do: state

  defp deliver(state, text) do
    send(state.owner, {:ws, self(), text})
    state
  end
end

defmodule Load.Browser do
  @moduledoc "Signs in like a browser and opens a topic's LiveView."

  def sign_in(base, email, password, ip) do
    {cookie, csrf} = get_page(base, "/users/sign-in", nil, ip)

    response =
      Req.post!(base <> "/users/sign-in",
        form: [
          _csrf_token: csrf,
          "user[email]": email,
          "user[password]": password
        ],
        headers: headers(cookie, ip),
        redirect: false,
        retry: false
      )

    if response.status != 302, do: raise("sign-in of #{email}: HTTP #{response.status}")
    merge_cookie(cookie, response)
  end

  @doc "Loads a page; returns the session cookie and the page's CSRF token (and the body)."
  def get_page(base, path, cookie, ip, with_body \\ false) do
    response =
      Req.get!(base <> path, headers: headers(cookie, ip), redirect: false, retry: false)

    if response.status != 200, do: raise("GET #{path}: HTTP #{response.status}")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, response.body)
    cookie = merge_cookie(cookie, response)
    if with_body, do: {cookie, csrf, response.body}, else: {cookie, csrf}
  end

  def headers(cookie, ip) do
    [{"x-forwarded-for", ip}] ++ if(cookie, do: [{"cookie", cookie}], else: [])
  end

  defp merge_cookie(cookie, response) do
    case Req.Response.get_header(response, "set-cookie") do
      [] -> cookie
      [set | _] -> set |> String.split(";") |> hd()
    end
  end

  @doc "The embedded TopicLive of a topic page: its id, session and static tokens."
  def live_view(body) do
    [_, id] = Regex.run(~r/id="(phx-[^"]+)"[^>]*data-phx-session=/, body)
    [_, session] = Regex.run(~r/data-phx-session="([^"]+)"/, body)
    [_, static] = Regex.run(~r/data-phx-static="([^"]*)"/, body)
    %{id: id, session: session, static: static}
  end
end

defmodule Load.Viewer do
  @moduledoc """
  One person with a topic open. Records when each marker first reaches them; as a writer,
  also commits text with new markers and records how long the server takes to answer.
  """

  @marker ~r/zq(\d+)q/

  def start(args), do: spawn_link(fn -> init(args) end)

  defp init(%{base: base, cookie: cookie, ip: ip, path: path} = args) do
    {cookie, csrf, body} = Load.Browser.get_page(base, path, cookie, ip, true)
    lv = Load.Browser.live_view(body)
    uri = URI.parse(base)

    ws_uri = %{
      uri
      | path: "/live/websocket",
        query: "_csrf_token=#{URI.encode_www_form(csrf)}&vsn=2.0.0"
    }

    {:ok, ws} =
      Load.WebSocket.start_link(self(), ws_uri, [
        {"cookie", cookie},
        {"origin", base},
        {"x-forwarded-for", ip}
      ])

    topic = "lv:" <> lv.id

    join = %{
      url: base <> path,
      params: %{_csrf_token: csrf, _mounts: 0},
      session: lv.session,
      static: lv.static
    }

    push(ws, ["1", "1", topic, "phx_join", join])

    state =
      Map.merge(args, %{
        ws: ws,
        topic: topic,
        ref: 1,
        seen: MapSet.new(),
        pending: %{},
        body: "",
        separator: "",
        count: 0
      })

    Process.send_after(self(), :heartbeat, 30_000)
    loop(state)
  end

  defp push(ws, message), do: Load.WebSocket.send_text(ws, Jason.encode!(message))

  defp start_writing(%{writer?: true} = state) do
    Process.send_after(self(), :write, :rand.uniform(3_000))
    state
  end

  defp start_writing(state), do: state

  defp loop(state) do
    receive do
      {:ws, _ws, text} -> state |> received(text) |> loop()
      :heartbeat -> state |> heartbeat() |> loop()
      :write -> state |> write() |> loop()
      # Writers start once everyone has joined (see the warm-up in Load.run/1).
      :start_writing -> state |> start_writing() |> loop()
      :stop -> :ok
    end
  end

  defp received(state, text) do
    now = System.monotonic_time(:microsecond)

    if String.starts_with?(text, ~s(["1","1",)) and text =~ ~s("status":"error"),
      do: IO.puts("join refused for #{state.index}: #{String.slice(text, 0, 200)}")

    state = ack(state, text, now)

    new =
      for [_, seq] <- Regex.scan(@marker, text),
          seq = String.to_integer(seq),
          not MapSet.member?(state.seen, seq),
          uniq: true,
          do: seq

    for seq <- new do
      case :ets.lookup(:load_sent, seq) do
        [{^seq, sent, topic, author}] when topic == state.topic_index and author != state.index ->
          :ets.insert(:load_latency, {seq, state.index, now - sent})

        _ ->
          :ok
      end
    end

    %{state | seen: Enum.reduce(new, state.seen, &MapSet.put(&2, &1))}
  end

  # The server's reply to a commit: the writer's own round trip.
  defp ack(state, text, now) do
    case Map.keys(state.pending) do
      [] ->
        state

      _ ->
        case Jason.decode!(text) do
          [_, ref, _, "phx_reply", %{"status" => status} = reply]
          when is_map_key(state.pending, ref) ->
            :ets.insert(:load_acks, {ref, now - state.pending[ref], status})
            sync(%{state | pending: Map.delete(state.pending, ref)}, find_reply(reply))

          _ ->
            state
        end
    end
  end

  # As the composer does (assets/js/composer.js): the server's text is the truth, and after a
  # Ctrl+Enter that closed the message the next text starts a new one.
  defp sync(state, %{"closed" => true}), do: %{state | body: ""}

  defp sync(state, %{"body" => body}) when is_binary(body) and body != "",
    do: %{state | body: body}

  defp sync(state, _reply), do: state

  defp find_reply(%{"closed" => _} = reply), do: reply
  defp find_reply(map) when is_map(map), do: Enum.find_value(Map.values(map), &find_reply/1)
  defp find_reply(_other), do: nil

  defp heartbeat(state) do
    ref = state.ref + 1
    push(state.ws, [nil, Integer.to_string(ref), "phoenix", "heartbeat", %{}])
    Process.send_after(self(), :heartbeat, 30_000)
    %{state | ref: ref}
  end

  # Enter every 2 to 4 seconds, as in a chat; every 15th Enter is Ctrl+Enter. Like the
  # composer, the text sent is what was sent before, the separator, the new words, and a
  # full stop (finishSentence), so the server sees an append, not an edit.
  defp write(state) do
    seq = :ets.update_counter(:load_seq, :seq, 1)
    count = state.count + 1
    ref = state.ref + 1
    break? = rem(count, 15) == 0
    words = "Word zq#{seq}q."
    body = if state.body == "", do: words, else: state.body <> state.separator <> words

    :ets.insert(
      :load_sent,
      {seq, System.monotonic_time(:microsecond), state.topic_index, state.index}
    )

    push(state.ws, [
      "1",
      Integer.to_string(ref),
      state.topic,
      "event",
      %{type: "hook", event: "commit", value: %{body: body, break: break?}}
    ])

    Process.send_after(self(), :write, 2_000 + :rand.uniform(2_000))
    pending = Map.put(state.pending, Integer.to_string(ref), System.monotonic_time(:microsecond))
    separator = if break?, do: "\n", else: " "
    %{state | ref: ref, count: count, body: body, separator: separator, pending: pending}
  end
end

defmodule Load.Run do
  @password "load test passphrase"

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          url: :string,
          users: :integer,
          topics: :integer,
          writers: :integer,
          duration: :integer,
          hot: :boolean
        ]
      )

    base = Keyword.get(opts, :url, "http://localhost:4000")
    users = Keyword.get(opts, :users, 200)
    topics = if opts[:hot], do: 1, else: Keyword.get(opts, :topics, 10)
    writers = Keyword.get(opts, :writers, 30)
    duration = Keyword.get(opts, :duration, 180)

    {:ok, _} = Application.ensure_all_started(:req)

    for table <- [:load_sent, :load_latency, :load_acks, :load_seq],
        do: :ets.new(table, [:named_table, :public, :set])

    :ets.delete(:load_latency)
    :ets.new(:load_latency, [:named_table, :public, :bag])
    :ets.insert(:load_seq, {:seq, 0})

    paths = topic_paths(base, topics)
    IO.puts("#{users} people, #{length(paths)} topic(s), #{writers} writing, #{duration} s")

    t0 = System.monotonic_time(:millisecond)

    cookies =
      1..users
      |> Task.async_stream(
        fn i -> {i, Load.Browser.sign_in(base, email(i), @password, ip(i))} end,
        max_concurrency: 4,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, pair} -> pair end)

    IO.puts("signed in: #{length(cookies)} in #{System.monotonic_time(:millisecond) - t0} ms")

    viewers =
      for {i, cookie} <- cookies do
        topic_index = rem(i, length(paths))

        pid =
          Load.Viewer.start(%{
            base: base,
            cookie: cookie,
            ip: ip(i),
            path: Enum.at(paths, topic_index),
            index: i,
            topic_index: topic_index,
            # Writers spread over the topics.
            writer?: i <= writers
          })

        Process.sleep(20)
        {pid, topic_index}
      end

    # Everyone joins first, then the writers start: the test measures the conversation, not
    # the arrival of 200 people at once. Joined while 30 people already wrote, a viewer lands
    # on their first unread message, further up, where new messages are counted instead of
    # shown (Long topics), and would receive none of them.
    Process.sleep(5_000)
    for {pid, _} <- viewers, do: send(pid, :start_writing)
    IO.puts("connected; warming up 10 s")
    Process.sleep(10_000)
    :ets.delete_all_objects(:load_latency)
    :ets.delete_all_objects(:load_acks)
    first_seq = :ets.lookup_element(:load_seq, :seq, 2)

    page_times = browse(base, paths, duration)
    last_seq = :ets.lookup_element(:load_seq, :seq, 2)
    Process.sleep(2_000)

    report(viewers, first_seq, last_seq, writers, duration, page_times)
    for {pid, _} <- viewers, do: send(pid, :stop)
  end

  # Meanwhile, other visitors load public pages: about 5 a second.
  defp browse(base, paths, duration) do
    stop_at = System.monotonic_time(:millisecond) + duration * 1_000
    pages = ["/", "/search?q=word", "/c/load-test" | paths]

    Stream.repeatedly(fn ->
      path = Enum.random(pages)
      started = System.monotonic_time(:microsecond)
      ip = "10.9.#{:rand.uniform(200)}.#{:rand.uniform(200)}"

      result =
        try do
          Load.Browser.get_page(base, path, nil, ip)
          :ok
        rescue
          error -> {:error, Exception.message(error)}
        end

      elapsed = System.monotonic_time(:microsecond) - started
      Process.sleep(max(0, 200 - div(elapsed, 1_000)))
      if result == :ok, do: elapsed, else: result
    end)
    |> Stream.take_while(fn _ -> System.monotonic_time(:millisecond) < stop_at end)
    |> Enum.to_list()
  end

  defp topic_paths(base, count) do
    {_, _, home} = Load.Browser.get_page(base, "/", nil, "10.9.0.2", true)
    [category | _] = Regex.scan(~r{href="(/c/load[^"/]*)"}, home) |> Enum.map(&List.last/1)
    {_, _, page} = Load.Browser.get_page(base, category, nil, "10.9.0.3", true)

    paths = Regex.scan(~r{href="(/t/[^"]+)"}, page) |> Enum.map(&List.last/1) |> Enum.uniq()
    if length(paths) < count, do: raise("load/seed.exs made only #{length(paths)} topics")
    Enum.take(paths, count)
  end

  defp report(viewers, first_seq, last_seq, writers, duration, page_times) do
    latencies = :ets.tab2list(:load_latency) |> Enum.map(&elem(&1, 2))
    acks = :ets.tab2list(:load_acks)

    sent =
      for {seq, _, topic, _author} <- :ets.tab2list(:load_sent),
          seq > first_seq,
          seq <= last_seq,
          do: topic

    viewers_per_topic = Enum.frequencies_by(viewers, &elem(&1, 1))
    expected = Enum.sum(for topic <- sent, do: viewers_per_topic[topic] - 1)

    delivered =
      :ets.tab2list(:load_latency)
      |> Enum.count(fn {seq, _, _} -> seq > first_seq and seq <= last_seq end)

    errors = Enum.count(acks, fn {_, _, status} -> status != "ok" end)

    IO.puts("""

    Commits: #{length(sent)} by #{writers} writers (#{Float.round(length(sent) / duration, 1)}/s)
    Deliveries to other viewers: #{delivered} of #{expected} expected
    Live latency, commit to other viewers (NF-01: p95 within 200 ms):
      #{stats(latencies)}
    Commit round trip for the writer:
      #{stats(Enum.map(acks, &elem(&1, 1)))}  (errors: #{errors})
    Public page loads (#{length(page_times)}, failed: #{Enum.count(page_times, &match?({:error, _}, &1))}):
      #{stats(Enum.filter(page_times, &is_integer/1))}
    """)
  end

  defp stats([]), do: "no samples"

  defp stats(us) do
    sorted = Enum.sort(us)
    pct = fn p -> Enum.at(sorted, min(length(sorted) - 1, trunc(p * length(sorted)))) / 1000 end

    "p50 #{Float.round(pct.(0.5), 1)} ms · p95 #{Float.round(pct.(0.95), 1)} ms · " <>
      "p99 #{Float.round(pct.(0.99), 1)} ms · max #{Float.round(List.last(sorted) / 1000, 1)} ms"
  end

  defp email(i), do: "load#{String.pad_leading(Integer.to_string(i), 4, "0")}@example.org"
  # Each person has an address of their own, as the rate limits count per address.
  defp ip(i), do: "10.8.#{div(i, 250)}.#{rem(i, 250) + 1}"
end

Load.Run.main(System.argv())
