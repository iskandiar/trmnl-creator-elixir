defmodule Trmnl.Renderer do
  def render(layout, events, family \\ []) do
    html = Trmnl.ScreenHTML.render(layout, events, DateTime.utc_now(), family)

    case Req.post(Application.fetch_env!(:trmnl, :renderer_url) <> "/render",
           json: %{html: html},
           headers: [
             {"authorization", "Bearer " <> Application.fetch_env!(:trmnl, :renderer_secret)}
           ],
           receive_timeout: 45_000,
           # Content updates can be rendering while an admin requests a preview.
           # Only retry a busy renderer; failures still retain the previous image.
           retry: fn
             _, %Req.Response{status: 503} -> true
             _, _ -> false
           end,
           retry_delay: fn attempt -> 250 * Integer.pow(2, attempt) end,
           max_retries: 5
         ) do
      {:ok, %{status: 200, body: <<137, 80, 78, 71, _::binary>> = png}} -> {:ok, png}
      _ -> {:error, :renderer_unavailable}
    end
  rescue
    _ -> {:error, :renderer_unavailable}
  end
end
