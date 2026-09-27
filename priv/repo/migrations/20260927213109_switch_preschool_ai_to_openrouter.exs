defmodule Trmnl.Repo.Migrations.SwitchPreschoolAiToOpenrouter do
  use Ecto.Migration

  def up do
    # Keep imported_mode as provenance and force fresh summaries with the new provider.
    execute "UPDATE preschool_menus SET mode = 'openrouter', error = NULL WHERE mode = 'gemini'"
  end

  def down do
    execute "UPDATE preschool_menus SET mode = 'gemini', error = NULL WHERE mode = 'openrouter'"
  end
end
