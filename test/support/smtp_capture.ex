# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# The callback names (handle_HELO, handle_DATA, ...) are set by gen_smtp's behaviour.
# credo:disable-for-this-file Credo.Check.Readability.FunctionNames
defmodule Idejo.SMTPCapture do
  @moduledoc """
  A local SMTP server for tests (AD-08): accepts mail on a free port and sends each message
  to the test process as `{:smtp_mail, from, to, data}`. With `auth: {user, password}` it
  requires that login.
  """
  @behaviour :gen_smtp_server_session

  @doc """
  Starts the server for the calling test and returns its port. It stops with the test.
  """
  def start!(opts \\ []) do
    name = :"smtp_capture_#{System.unique_integer([:positive])}"
    callback = [test_pid: self(), auth: opts[:auth]]

    {:ok, _pid} =
      :gen_smtp_server.start(name, __MODULE__,
        address: {127, 0, 0, 1},
        port: 0,
        domain: ~c"localhost",
        sessionoptions: [callbackoptions: callback]
      )

    ExUnit.Callbacks.on_exit(fn -> :gen_smtp_server.stop(name) end)
    :ranch.get_port(name)
  end

  @impl true
  def init(hostname, _count, _address, options),
    do: {:ok, [hostname, " ESMTP test"], Map.new(options)}

  @impl true
  def handle_HELO(_hostname, state), do: {:ok, state}

  @impl true
  def handle_EHLO(_hostname, extensions, %{auth: nil} = state), do: {:ok, extensions, state}

  def handle_EHLO(_hostname, extensions, state),
    do: {:ok, extensions ++ [{~c"AUTH", ~c"PLAIN LOGIN"}], state}

  @impl true
  def handle_AUTH(type, user, password, %{auth: {user, password}} = state)
      when type in [:plain, :login],
      do: {:ok, Map.put(state, :authenticated, true)}

  def handle_AUTH(_type, _user, _password, _state), do: :error

  @impl true
  def handle_MAIL(_from, %{auth: nil} = state), do: {:ok, state}
  def handle_MAIL(_from, %{authenticated: true} = state), do: {:ok, state}
  def handle_MAIL(_from, state), do: {:error, ~c"530 Authentication required", state}

  @impl true
  def handle_MAIL_extension(_extension, state), do: {:ok, state}

  @impl true
  def handle_RCPT(_to, state), do: {:ok, state}

  @impl true
  def handle_RCPT_extension(_extension, state), do: {:ok, state}

  @impl true
  def handle_DATA(from, to, data, state) do
    send(state.test_pid, {:smtp_mail, from, to, data})
    {:ok, ~c"1", state}
  end

  @impl true
  def handle_RSET(state), do: state

  @impl true
  def handle_VRFY(_address, state), do: {:error, ~c"252 VRFY disabled", state}

  @impl true
  def handle_other(verb, _args, state),
    do: {[~c"500 Error: command not recognized : '", verb, ~c"'"], state}

  @impl true
  def handle_STARTTLS(state), do: state

  @impl true
  def handle_info(_info, state), do: {:noreply, state}

  @impl true
  def handle_error(_class, _details, state), do: {:ok, state}

  @impl true
  def code_change(_old, state, _extra), do: {:ok, state}

  @impl true
  def terminate(reason, state), do: {:ok, reason, state}
end
