# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.EmailUnsubscribeHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.EmailUnsubscribeController`.
  """
  use IdejoWeb, :html

  embed_templates "email_unsubscribe_html/*"
end
