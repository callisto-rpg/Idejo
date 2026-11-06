# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

defmodule Idejo.Community.Profile do
  @moduledoc """
  The member's profile at the provider (AC-09 with the community menu; steward decisions,
  2026-11-06): where the provider keeps a public username and picture for each person, a new
  member starts with them, and linking an existing account offers the provider this account's
  username and picture (it keeps them only when it has none). Optional and generic, like the
  community menu: `<IDEJO_COMMUNITY_URL>/profile`, or `<registry>/account/api/profile` for a
  server connected from Admin → Idejo ID; unset, nothing is asked.

  `GET ?subject=` → `{"username", "picture"}` (the picture's address, at the provider's own
  host only); `POST {"subject", "username", "picture"}` (the avatar's WebP in Base64), both
  with the OpenID Connect client's id and secret (HTTP Basic), two seconds at most (three for
  the picture). Any failure is silent: sign-in and linking never wait on it.
  """
  alias Idejo.Accounts
  alias Idejo.Accounts.{OIDC, OIDCRegistry, User}

  @max_picture 512_000

  @doc "Where profiles are asked, or nil."
  @spec url() :: String.t() | nil
  def url do
    community = (Application.get_env(:idejo, :community) || [])[:url]

    cond do
      community -> String.trim_trailing(community, "/") <> "/profile"
      registry = OIDCRegistry.config()[:registry_url] -> registry <> "/account/api/profile"
      true -> nil
    end
  end

  @doc "The provider's profile of `subject`: `%{username:, picture:}`, or nil."
  @spec fetch(String.t()) :: %{username: String.t() | nil, picture: String.t() | nil} | nil
  def fetch(subject) when is_binary(subject) do
    with url when is_binary(url) <- url(),
         oidc when is_list(oidc) <- OIDC.config(),
         {:ok, %{status: 200, body: %{} = body}} <-
           Req.get(request(url, oidc, params: [subject: subject])) do
      %{username: text(body["username"]), picture: picture_url(body["picture"], oidc)}
    else
      _ -> nil
    end
  end

  def fetch(_subject), do: nil

  @doc "Gives `user` the profile's picture, when it has one and the user none."
  @spec adopt_picture(User.t(), map() | nil) :: :ok
  def adopt_picture(%User{avatar_id: nil} = user, %{picture: "http" <> _ = picture}) do
    with oidc when is_list(oidc) <- OIDC.config(),
         {:ok, %{status: 200, body: body}}
         when is_binary(body) and byte_size(body) <= @max_picture <-
           Req.get(request(picture, oidc, auth: nil, decode_body: false, receive_timeout: 3_000)) do
      path = Path.join(System.tmp_dir!(), "idejo-profile-#{System.unique_integer([:positive])}")

      try do
        File.write!(path, body)
        _ = Accounts.set_avatar(user, path)
      after
        File.rm(path)
      end
    end

    :ok
  end

  def adopt_picture(_user, _profile), do: :ok

  @doc """
  Offers the provider `user`'s username and picture for `subject` (just linked): it keeps
  each only when it has none.
  """
  @spec share(User.t(), String.t()) :: :ok
  def share(%User{} = user, subject) do
    with url when is_binary(url) <- url(),
         oidc when is_list(oidc) <- OIDC.config() do
      body =
        %{subject: subject, username: user.username}
        |> put_picture(user)

      _ = Req.post(request(url, oidc, json: body))
    end

    :ok
  end

  defp put_picture(body, %User{avatar_id: nil}), do: body

  defp put_picture(body, %User{avatar_id: id}) do
    path = Path.join(Application.fetch_env!(:idejo, :uploads_dir), id <> ".webp")

    case File.read(path) do
      {:ok, bytes} when byte_size(bytes) <= @max_picture ->
        Map.put(body, :picture, Base.encode64(bytes))

      _ ->
        body
    end
  end

  defp request(url, oidc, options) do
    Req.new(
      url: url,
      auth: {:basic, oidc[:client_id] <> ":" <> oidc[:client_secret]},
      receive_timeout: 2_000,
      connect_options: [timeout: 2_000],
      retry: false,
      redirect: false
    )
    |> Req.merge(options)
    |> Req.merge(Application.get_env(:idejo, :community_req_options, []))
  end

  # A username fit to use: Idejo's characters only, never an address.
  defp text(value) when is_binary(value) do
    if value =~ ~r/\A[A-Za-z0-9_]{3,30}\z/, do: value
  end

  defp text(_value), do: nil

  # Only from the provider's own host: never sends this server elsewhere.
  defp picture_url("http" <> _ = url, oidc) do
    %URI{host: host} = URI.parse(url)
    if host != nil and host == URI.parse(oidc[:issuer]).host, do: url
  end

  defp picture_url(_url, _oidc), do: nil
end
