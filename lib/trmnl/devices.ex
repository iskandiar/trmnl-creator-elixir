defmodule Trmnl.Devices do
  import Ecto.Query
  alias Trmnl.{Repo, Device, Crypto}
  def device, do: Repo.get(Device, 1)

  def allow_pairing(mac) do
    mac = String.upcase(String.trim(mac))

    if Regex.match?(~r/\A(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\z/, mac) do
      (device() || %Device{id: 1})
      |> Ecto.Changeset.change(mac: mac, token_hash: nil, pair_until: DateTime.add(now(), 600))
      |> Repo.insert_or_update()
    else
      {:error, "Enter a MAC address such as AA:BB:CC:DD:EE:FF."}
    end
  end

  def pair(mac) do
    Repo.transaction(fn ->
      d = Repo.one(from d in Device, where: d.id == 1, lock: "FOR UPDATE")

      if d && d.mac == String.upcase(mac) && d.pair_until &&
           DateTime.compare(d.pair_until, now()) == :gt do
        token = Crypto.random()

        Repo.update!(
          Ecto.Changeset.change(d,
            token_hash: Crypto.hash(token),
            pair_until: nil,
            last_contact: now()
          )
        )

        token
      else
        Repo.rollback(:unauthorized)
      end
    end)
  end

  def authenticate(mac, token) do
    d = device()

    if d && d.mac == String.upcase(mac) && d.token_hash &&
         Plug.Crypto.secure_compare(d.token_hash, Crypto.hash(token)),
       do: {:ok, d},
       else: {:error, :unauthorized}
  end

  def contact(d, battery, rssi) do
    attrs = [last_contact: now()]
    attrs = if numeric?(battery), do: Keyword.put(attrs, :battery, battery), else: attrs
    attrs = if numeric?(rssi), do: Keyword.put(attrs, :rssi, rssi), else: attrs
    Repo.update!(Ecto.Changeset.change(d, attrs))
  end

  defp numeric?(v),
    do: is_binary(v) and byte_size(v) < 16 and Regex.match?(~r/\A-?\d+(\.\d+)?\z/, v)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
