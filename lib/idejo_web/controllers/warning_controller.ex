# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.WarningController do
  @moduledoc """
  MO-02 "warn" (steward request, 2026-11-09): the warned member's "I understand" without
  JavaScript (`POST /warnings/seen`): every warning waiting is marked seen, then back to the
  page they were on.
  """
  use IdejoWeb, :controller

  alias Idejo.Moderation.Warnings
  alias IdejoWeb.ReturnBack

  def seen(conn, _params) do
    :ok = Warnings.acknowledge(conn.assigns.current_scope.user)
    redirect(conn, to: ReturnBack.path(conn, %{"return" => "back"}) || ~p"/")
  end
end
