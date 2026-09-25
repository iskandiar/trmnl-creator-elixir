defmodule Trmnl.Crypto do
  def encrypt(value) do
    iv = :crypto.strong_rand_bytes(12)

    {data, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key(),
        iv,
        Jason.encode!(value),
        "trmnl:v1",
        true
      )

    <<1, iv::binary-size(12), tag::binary-size(16), data::binary>>
  end

  def decrypt(<<1, iv::binary-size(12), tag::binary-size(16), data::binary>>) do
    :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, data, "trmnl:v1", tag, false)
    |> Jason.decode!()
  end

  defp key, do: Application.fetch_env!(:trmnl, :encryption_key)
  def random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  def hash(value), do: :crypto.hash(:sha256, value)

  def equal?(a, b) when is_binary(a) and is_binary(b),
    do: Plug.Crypto.secure_compare(hash(a), hash(b))

  def equal?(_, _), do: false
end
