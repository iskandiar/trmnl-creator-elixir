defmodule Trmnl.Weather do
  use GenServer

  @url "https://api.met.no/weatherapi/locationforecast/2.0/compact"
  @user_agent "TRMNL-Creator/0.1 https://github.com/iskandiar/trmnl-creator-elixir"

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def coordinates(block) do
    with {:ok, lat} <- coordinate(block["latitude"], -90, 90),
         {:ok, lon} <- coordinate(block["longitude"], -180, 180) do
      {:ok, {lat, lon}}
    end
  end

  def forecast(block, server \\ __MODULE__) do
    with {:ok, coordinates} <- coordinates(block) do
      GenServer.call(server, {:forecast, coordinates}, 60_000)
    end
  end

  defp coordinate(value, min, max) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} when number >= min and number <= max ->
        {:ok, :erlang.float_to_binary(Float.floor(number, 4), decimals: 4)}

      _ ->
        {:error, :location}
    end
  end

  defp coordinate(_, _, _), do: {:error, :location}

  @impl true
  def init(opts) do
    {:ok,
     %{
       cache: %{},
       request_options: Keyword.get(opts, :request_options, []),
       clock: Keyword.get(opts, :clock, &DateTime.utc_now/0)
     }}
  end

  @impl true
  def handle_call({:forecast, key}, _, state) do
    now = state.clock.()
    cached = Map.get(state.cache, key)

    entry =
      if cached && DateTime.compare(now, cached.expires) == :lt do
        cached
      else
        fetch(key, cached, now, state.request_options)
      end

    # Bound memory for abandoned draft locations, retaining the newest entries.
    cache =
      state.cache
      |> Map.put(key, entry)
      |> Enum.sort_by(fn {_, e} -> DateTime.to_unix(e.expires) end, :desc)
      |> Enum.take(100)
      |> Map.new()

    reply = if entry.rows == [], do: {:error, :unavailable}, else: {:ok, entry}
    {:reply, reply, %{state | cache: cache}}
  end

  defp fetch({lat, lon}, cached, now, options) do
    headers = [{"user-agent", @user_agent}]

    headers =
      if cached && cached.modified,
        do: [{"if-modified-since", cached.modified} | headers],
        else: headers

    result =
      Req.get(
        Keyword.merge(
          [
            url: @url,
            params: [lat: lat, lon: lon],
            headers: headers,
            receive_timeout: 5_000,
            connect_options: [timeout: 5_000],
            retry: false
          ],
          options
        )
      )

    case result do
      {:ok, %Req.Response{status: status, body: body} = response} when status in [200, 203] ->
        case rows(body) do
          [] ->
            failed(cached, now)

          rows ->
            %{
              rows: rows,
              expires: expires(response, now),
              modified: List.first(Req.Response.get_header(response, "last-modified")),
              fetched_at: now,
              stale: false
            }
        end

      {:ok, %Req.Response{status: 304} = response} when not is_nil(cached) ->
        %{cached | expires: expires(response, now), fetched_at: now, stale: false}

      _ ->
        failed(cached, now)
    end
  rescue
    _ -> failed(cached, now)
  end

  defp failed(cached, now) do
    cached = cached || %{rows: [], modified: nil, fetched_at: now}
    Map.merge(cached, %{expires: DateTime.add(now, 300, :second), stale: true})
  end

  defp expires(response, now) do
    value = List.first(Req.Response.get_header(response, "expires"))

    parsed =
      if value, do: :httpd_util.convert_request_date(String.to_charlist(value)), else: :bad_date

    date =
      case parsed do
        {{year, month, day}, {hour, minute, second}} ->
          with {:ok, date} <- Date.new(year, month, day),
               {:ok, time} <- Time.new(hour, minute, second),
               {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC"),
               do: datetime

        _ ->
          nil
      end

    base =
      if match?(%DateTime{}, date) && DateTime.compare(date, now) == :gt,
        do: date,
        else: DateTime.add(now, 600, :second)

    DateTime.add(base, :rand.uniform(60), :second)
  end

  defp rows(%{"properties" => %{"timeseries" => series}}) when is_list(series) do
    Enum.flat_map(series, fn
      %{
        "time" => time,
        "data" =>
          %{"instant" => %{"details" => %{"air_temperature" => temp, "wind_speed" => wind}}} =
              data
      }
      when is_binary(time) and is_number(temp) and is_number(wind) ->
        case DateTime.from_iso8601(time) do
          {:ok, at, _} ->
            hour = data["next_1_hours"] || %{}
            rain = get_in(hour, ["details", "precipitation_amount"])
            symbol = get_in(hour, ["summary", "symbol_code"])

            [
              %{
                at: at,
                temperature: temp,
                wind: wind,
                rain: if(is_number(rain) and rain >= 0, do: rain),
                symbol: if(is_binary(symbol), do: symbol, else: "")
              }
            ]

          _ ->
            []
        end

      _ ->
        []
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.at))
  end

  defp rows(_), do: []
end
