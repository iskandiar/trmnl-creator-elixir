layout = %{
  "blocks" => [
    %{
      "id" => "setup",
      "type" => "text",
      "x" => 0,
      "y" => 0,
      "w" => 20,
      "h" => 12,
      "title" => "TRMNL · Calendar Studio",
      "font_size" => 24,
      "text" =>
        "Twój ekran jest gotowy.\n\nPołącz kalendarze, ułóż bloki i wybierz Publikuj na TRMNL."
    }
  ]
}

{:ok, image} = Trmnl.Renderer.render(layout, [])
File.write!("priv/static/setup.png", image)

{_, 0} =
  System.cmd(System.get_env("MAGICK_BIN", "convert"), [
    "priv/static/setup.png",
    "-type",
    "bilevel",
    "-compress",
    "none",
    "BMP3:priv/static/setup.bmp"
  ])
