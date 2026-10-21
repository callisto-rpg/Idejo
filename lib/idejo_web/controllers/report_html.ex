# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ReportHTML do
  @moduledoc """
  Pages rendered by `IdejoWeb.ReportController`.
  """
  use IdejoWeb, :html

  embed_templates "report_html/*"
end
