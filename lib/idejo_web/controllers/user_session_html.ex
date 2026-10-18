# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.UserSessionHTML do
  use IdejoWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:idejo, Idejo.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
