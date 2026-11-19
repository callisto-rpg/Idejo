# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule IdejoWeb.Api.AssetLinksControllerTest do
  @moduledoc "IX-03: `/.well-known/assetlinks.json` names the official app and its keys."
  use IdejoWeb.ConnCase, async: false

  @official String.duplicate("14:", 31) <> "6D"
  @extra String.duplicate("AA:", 31) <> "BB"

  setup do
    official = Application.get_env(:idejo, :android_fingerprints)
    extra = Application.get_env(:idejo, :extra_android_fingerprints)

    on_exit(fn ->
      Application.put_env(:idejo, :android_fingerprints, official)

      if extra,
        do: Application.put_env(:idejo, :extra_android_fingerprints, extra),
        else: Application.delete_env(:idejo, :extra_android_fingerprints)
    end)
  end

  test "IX-03 the app and every fingerprint, official first, each once", %{conn: conn} do
    Application.put_env(:idejo, :android_fingerprints, [@official])
    Application.put_env(:idejo, :extra_android_fingerprints, [@extra, @official])

    assert [statement] = conn |> get("/.well-known/assetlinks.json") |> json_response(200)
    assert statement["relation"] == ["delegate_permission/common.handle_all_urls"]
    assert statement["target"]["namespace"] == "android_app"
    assert statement["target"]["package_name"] == "org.idejo.app"
    assert statement["target"]["sha256_cert_fingerprints"] == [@official, @extra]
  end

  test "IX-03 with no fingerprint at all, not found", %{conn: conn} do
    Application.put_env(:idejo, :android_fingerprints, [])
    Application.delete_env(:idejo, :extra_android_fingerprints)

    assert conn |> get("/.well-known/assetlinks.json") |> response(404)
  end
end
