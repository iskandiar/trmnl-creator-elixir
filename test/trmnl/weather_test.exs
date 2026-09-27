defmodule Trmnl.WeatherTest do
  use ExUnit.Case, async: true
  alias Trmnl.{Weather, WeatherHTML}

  @location %{"latitude" => "52.2297123", "longitude" => "21.0122123"}
  @now ~U[2026-09-27 10:30:00Z]

  setup do
    clock = start_supervised!({Agent, fn -> @now end})

    server =
      start_supervised!(
        {Weather,
         name: nil,
         clock: fn -> Agent.get(clock, & &1) end,
         request_options: [plug: {Req.Test, __MODULE__}]}
      )

    Req.Test.allow(__MODULE__, self(), server)
    %{server: server, clock: clock}
  end

  test "validates coordinates before sending any request", %{server: server} do
    assert {:ok, {"52.2297", "21.0122"}} = Weather.coordinates(@location)

    for location <- [
          %{},
          %{"latitude" => "91", "longitude" => "0"},
          %{"latitude" => "0", "longitude" => "-181"},
          %{"latitude" => "1x", "longitude" => "0"}
        ] do
      assert {:error, :location} = Weather.forecast(location, server)
    end
  end

  test "identifies requests, caches until Expires and revalidates with Last-Modified", %{
    server: server,
    clock: clock
  } do
    parent = self()

    Req.Test.stub(__MODULE__, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params == %{"lat" => "52.2297", "lon" => "21.0122"}
      assert [agent] = Plug.Conn.get_req_header(conn, "user-agent")
      assert agent =~ "github.com/iskandiar/trmnl-creator-elixir"
      send(parent, :weather_requested)

      conn
      |> Plug.Conn.put_resp_header("expires", "Sun, 27 Sep 2026 11:00:00 GMT")
      |> Plug.Conn.put_resp_header("last-modified", "Sun, 27 Sep 2026 10:00:00 GMT")
      |> Req.Test.json(payload())
    end)

    assert {:ok, first} = Weather.forecast(@location, server)
    assert_receive :weather_requested
    assert {:ok, ^first} = Weather.forecast(@location, server)
    refute_received :weather_requested

    Agent.update(clock, fn _ -> ~U[2026-09-27 11:02:00Z] end)

    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "if-modified-since") == [
               "Sun, 27 Sep 2026 10:00:00 GMT"
             ]

      conn
      |> Plug.Conn.put_resp_header("expires", "Sun, 27 Sep 2026 12:00:00 GMT")
      |> Plug.Conn.send_resp(304, "")
    end)

    assert {:ok, refreshed} = Weather.forecast(@location, server)
    assert refreshed.rows == first.rows
    refute refreshed.stale
  end

  test "outages retain and mark cached forecasts; empty cache reports unavailable", %{
    server: server,
    clock: clock
  } do
    Req.Test.stub(__MODULE__, &Req.Test.json(&1, payload()))
    assert {:ok, first} = Weather.forecast(@location, server)
    Agent.update(clock, fn _ -> ~U[2026-09-27 11:30:00Z] end)
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 503, "offline"))
    assert {:ok, stale} = Weather.forecast(@location, server)
    assert stale.rows == first.rows
    assert stale.stale

    assert {:error, :unavailable} =
             Weather.forecast(%{"latitude" => "0", "longitude" => "0"}, server)

    assert WeatherHTML.render({:ok, stale}, @now) =~ "zapisane dane"
  end

  test "renders Polish forecast, units, local time and attribution without claiming missing rain is zero",
       %{server: server} do
    Req.Test.stub(__MODULE__, &Req.Test.json(&1, payload()))
    result = Weather.forecast(@location, server)
    document = WeatherHTML.render(result, @now) |> LazyHTML.from_fragment()
    assert document |> LazyHTML.query(".weather-main") |> LazyHTML.text() == "18.5°C Pochmurno"
    text = LazyHTML.text(document)
    assert text =~ "27.09 12:00"
    assert text =~ "Wiatr 3.2 m/s"
    assert text =~ "Opady 0.4 mm/1 h"
    assert text =~ "Opady: brak danych"
    assert document |> LazyHTML.query(".weather-source") |> LazyHTML.text() =~ "MET Norway"
    assert WeatherHTML.render(result, ~U[2026-10-01 00:00:00Z]) =~ "niedostępna"
  end

  test "malformed responses degrade to unavailable", %{server: server} do
    Req.Test.stub(
      __MODULE__,
      &Req.Test.json(&1, %{"properties" => %{"timeseries" => [%{"time" => "bad"}]}})
    )

    assert {:error, :unavailable} = Weather.forecast(@location, server)
  end

  defp payload do
    %{
      "properties" => %{
        "timeseries" =>
          for hour <- 10..16 do
            data = %{
              "instant" => %{"details" => %{"air_temperature" => 18.5, "wind_speed" => 3.2}}
            }

            data =
              if hour == 10,
                do:
                  Map.put(data, "next_1_hours", %{
                    "details" => %{"precipitation_amount" => 0.4},
                    "summary" => %{"symbol_code" => "cloudy"}
                  }),
                else: data

            %{"time" => "2026-09-27T#{hour}:00:00Z", "data" => data}
          end
      }
    }
  end
end
