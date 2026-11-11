# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  # AP-17: under /api, the API's one error shape, whatever went wrong (a body that is not
  # JSON, a crash).
  def render(template, %{conn: %Plug.Conn{path_info: ["api" | _]}}) do
    code =
      case template do
        "400.json" -> "bad_request"
        "404.json" -> "not_found"
        "413.json" -> "too_large"
        "415.json" -> "bad_request"
        _ -> "internal"
      end

    %{
      "error" => %{
        "code" => code,
        "message" => Phoenix.Controller.status_message_from_template(template),
        "details" => %{}
      }
    }
  end

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
