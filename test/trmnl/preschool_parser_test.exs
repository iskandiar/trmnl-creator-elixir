defmodule Trmnl.PreschoolParserTest do
  use ExUnit.Case, async: true
  alias Trmnl.PreschoolParser
  @html File.read!("test/fixtures/preschool_menu.html")

  test "decodes Polish HTML, preserves exact dates and separates all three meals" do
    assert {:ok, [monday, tuesday]} = PreschoolParser.parse(@html)

    assert monday == %{
             "date" => "2026-09-28",
             "breakfast" => "kanapki z serem & pomidorem",
             "lunch" => "zupa warzywna ryż z kurczakiem",
             "snack" => "jabłko"
           }

    assert tuesday["date"] == "2026-09-29"
    assert tuesday["snack"] == "jogurt"
    refute tuesday["snack"] =~ "Informacje"
  end

  test "rejects incomplete, duplicate, invalid-date and unsupported image-only menus" do
    for html <- [
          String.replace(@html, "Podwieczorek:", "Przekąska:"),
          String.replace(@html, "29.09.2026", "28.09.2026"),
          String.replace(@html, "28. 09. 2026", "32. 09. 2026"),
          "<img src='menu.png'>",
          "unavailable"
        ] do
      assert {:error, :invalid_menu} = PreschoolParser.parse(html)
    end
  end
end
