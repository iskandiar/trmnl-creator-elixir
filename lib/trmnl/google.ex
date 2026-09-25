defmodule Trmnl.Google do
  @api "https://www.googleapis.com/calendar/v3"
  def configured? do
    Enum.all?([:google_client_id, :google_client_secret], fn key ->
      value = Application.get_env(:trmnl, key)
      is_binary(value) and String.trim(value) != ""
    end)
  end

  def authorization_url(state) do
    "https://accounts.google.com/o/oauth2/v2/auth?" <>
      URI.encode_query(%{
        client_id: env(:google_client_id),
        redirect_uri: env(:google_redirect_uri),
        response_type: "code",
        scope: "https://www.googleapis.com/auth/calendar.readonly",
        access_type: "offline",
        prompt: "consent select_account",
        state: state
      })
  end

  def exchange(code),
    do:
      token(grant_type: "authorization_code", code: code, redirect_uri: env(:google_redirect_uri))

  def refresh(refresh), do: token(grant_type: "refresh_token", refresh_token: refresh)

  defp token(params) do
    request(:post, "https://oauth2.googleapis.com/token",
      form:
        params ++ [client_id: env(:google_client_id), client_secret: env(:google_client_secret)]
    )
  end

  def calendars(token),
    do: pages("#{@api}/users/me/calendarList", token, [maxResults: 250], [], MapSet.new())

  def events(token, id, from, until) do
    pages(
      "#{@api}/calendars/#{URI.encode(id, &URI.char_unreserved?/1)}/events",
      token,
      [
        singleEvents: true,
        showDeleted: true,
        timeMin: from,
        timeMax: until,
        maxResults: 2500,
        timeZone: "Europe/Warsaw"
      ],
      [],
      MapSet.new()
    )
  end

  defp pages(url, token, params, acc, seen) do
    with {:ok, body} <-
           request(:get, url, headers: [{"authorization", "Bearer " <> token}], params: params) do
      items = acc ++ Map.get(body, "items", [])

      case body["nextPageToken"] do
        nil ->
          {:ok, items}

        next ->
          if MapSet.member?(seen, next) or MapSet.size(seen) >= 1000 do
            {:error, :pagination_loop}
          else
            pages(
              url,
              token,
              Keyword.put(params, :pageToken, next),
              items,
              MapSet.put(seen, next)
            )
          end
      end
    end
  end

  defp request(method, url, opts) do
    options = Application.get_env(:trmnl, :google_req_options, [])

    case Req.request(
           [method: method, url: url, retry: false, receive_timeout: 15_000] ++ opts ++ options
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, _} -> {:error, :network}
    end
  end

  defp env(key), do: Application.fetch_env!(:trmnl, key)
end
