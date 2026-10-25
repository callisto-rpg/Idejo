# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.FakePushService do
  @moduledoc """
  A push service for tests (PN-15), served by Bandit on a free local port (Bypass would
  need ranch 1, and the lock has ranch 2). `start!/0` points `Idejo.Push.Sender` at it
  (`config :idejo, :push_target`) for the calling test, which must not be async.

  Each request is sent to the test process as `{:push_request, request}`, a map with
  `:method`, `:host` (the endpoint's host), `:path`, `:headers` and `:body`. It answers 201,
  or what `respond/2` queued, in order: `{status, headers}`.
  """
  @behaviour Plug

  @doc "Starts the service for the calling test; returns its name, for `respond/2`."
  def start! do
    {:ok, responses} = Agent.start_link(fn -> [] end)

    {:ok, server} =
      Bandit.start_link(
        plug: {__MODULE__, %{test: self(), responses: responses}},
        ip: :loopback,
        port: 0,
        startup_log: false
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_env(:idejo, :push_target)
    Application.put_env(:idejo, :push_target, "http://127.0.0.1:#{port}")

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:idejo, :push_target, previous),
        else: Application.delete_env(:idejo, :push_target)
    end)

    responses
  end

  @doc "Queues the answers to the next requests: `{status, headers}` each."
  def respond(responses, answers), do: Agent.update(responses, &(&1 ++ answers))

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, %{test: test, responses: responses}) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    send(
      test,
      {:push_request,
       %{
         method: conn.method,
         host: Plug.Conn.get_req_header(conn, "x-push-host") |> List.first(),
         path:
           conn.request_path <>
             if(conn.query_string == "", do: "", else: "?" <> conn.query_string),
         headers: Map.new(conn.req_headers),
         body: body
       }}
    )

    {status, headers} =
      Agent.get_and_update(responses, fn
        [next | rest] -> {next, rest}
        [] -> {{201, []}, []}
      end)

    conn |> Plug.Conn.merge_resp_headers(headers) |> Plug.Conn.send_resp(status, "")
  end
end
