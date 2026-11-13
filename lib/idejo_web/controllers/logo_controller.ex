# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.LogoController do
  @moduledoc """
  AD-11 (steward decision, 2026-11-06): `GET /logo`, the forum's logo at a fixed public address
  (no session), for directories of forums and link previews: a redirect to the forum's own logo
  (`Idejo.Settings.Logo`, an upload), or the small idejo logo when it has none. Cached an hour,
  so a new logo shows within the hour.
  """
  use IdejoWeb, :controller

  alias Idejo.Settings.Logo

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> redirect(to: Logo.url())
  end
end
