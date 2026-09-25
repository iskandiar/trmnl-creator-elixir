defmodule TrmnlWeb.FamilyEditor do
  import Phoenix.Component
  import Phoenix.LiveView
  alias Trmnl.{Family, FamilySchedule}

  def init(socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Trmnl.PubSub, "family")

    socket
    |> assign(family_kind: "today_tomorrow", family_notice: nil)
    |> reset_form()
    |> refresh()
  end

  def refresh(socket) do
    items = Family.list(socket.assigns.family_kind)

    socket
    |> assign(family_empty: items == [], family_today: FamilySchedule.today())
    |> stream(:family_items, items, reset: true)
  end

  def handle_event("module", %{"kind" => kind}, socket)
      when kind in ~w(today_tomorrow dinner reminders countdowns family_note) do
    {:noreply,
     socket |> assign(family_kind: kind, family_notice: nil) |> reset_form() |> refresh()}
  end

  def handle_event("new", _, socket), do: {:noreply, reset_form(socket)}

  def handle_event("edit", %{"id" => id}, socket) do
    case Family.get(id) do
      %{kind: kind} = item when kind == socket.assigns.family_kind ->
        {:noreply, assign_form(socket, item)}

      _ ->
        {:noreply,
         assign(socket, family_notice: "Ten wpis już nie istnieje. Odświeżono listę.")
         |> refresh()}
    end
  end

  def handle_event("save", %{"family" => attrs}, socket) do
    item = socket.assigns.family_item
    result = if item.id, do: Family.update(item, attrs), else: Family.create(item.kind, attrs)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           family_notice:
             "Zapisano treść. Opublikowany ekran odświeży się automatycznie; szkic układu pozostaje bez zmian."
         )
         |> reset_form()
         |> refresh()}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         assign(socket,
           family_form:
             to_form(cs, as: :family, id: "family-#{socket.assigns.family_form_epoch}"),
           family_notice:
             "Sprawdź pola formularza. Jeśli wpis zmieniono w innej karcie, otwórz go ponownie."
         )}

      _ ->
        {:noreply, assign(socket, family_notice: "Nie udało się zapisać. Spróbuj ponownie.")}
    end
  end

  def handle_event(action, %{"id" => id}, socket)
      when action in ["delete", "complete", "restore"] do
    case Family.get(id) do
      %{kind: kind} = item when kind == socket.assigns.family_kind ->
        result =
          case action do
            "delete" -> Family.delete(item)
            "complete" when kind in ["reminders", "today_tomorrow"] -> Family.complete(item)
            "restore" when kind in ["reminders", "today_tomorrow"] -> Family.restore(item)
            _ -> {:error, :invalid_action}
          end

        case result do
          {:ok, _} ->
            socket =
              if socket.assigns.family_item.id == item.id, do: reset_form(socket), else: socket

            {:noreply,
             socket
             |> assign(family_notice: "Zapisano zmianę. Ekran odświeży się automatycznie.")
             |> refresh()}

          _ ->
            {:noreply,
             assign(socket,
               family_notice: "Wpis zmienił się w innej karcie. Odśwież listę i spróbuj ponownie."
             )
             |> refresh()}
        end

      _ ->
        {:noreply, refresh(socket)}
    end
  end

  defp reset_form(socket), do: assign_form(socket, Family.new(socket.assigns.family_kind))

  defp assign_form(socket, item) do
    epoch = Map.get(socket.assigns, :family_form_epoch, 0) + 1

    assign(socket,
      family_item: item,
      family_form: to_form(Family.change(item), as: :family, id: "family-#{epoch}"),
      family_form_epoch: epoch
    )
  end
end
