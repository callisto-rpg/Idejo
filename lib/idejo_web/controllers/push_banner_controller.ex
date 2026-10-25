# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PushBannerController do
  @moduledoc """
  "Not now" on the notifications banner (PN-21): `POST /push/banner/dismiss`, sent with
  `fetch` by `assets/js/push_banner.js` (the banner shows only with JavaScript). Recorded on
  the server, so the banner stays away on every device for 14 days. Answers 204.
  """
  use IdejoWeb, :controller

  alias Idejo.Push

  def dismiss(conn, _params) do
    {:ok, _} = Push.dismiss_banner(conn.assigns.current_scope.user)
    send_resp(conn, 204, "")
  end
end
