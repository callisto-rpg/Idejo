# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.PrivacyHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.PrivacyController`.
  """
  use IdejoWeb, :html

  alias Idejo.Messages.Body

  embed_templates "privacy_html/*"
end
