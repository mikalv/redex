defmodule Redex.Command.INFO do
  use Redex.Command

  @sections ["keyspace"]

  def exec([]), do: section(:all)
  def exec([section]), do: String.downcase(section) |> section()
  def exec(_), do: wrong_arg_error("INFO")

  def section(:all) do
    for section <- @sections do
      apply(__MODULE__, :"#{section}", [])
    end
    |> Enum.join()
  end

  def section(section) when section in @sections do
    apply(__MODULE__, :"#{section}", [])
  end

  def section(_section), do: ""

  def keyspace do
    now = System.os_time(:millisecond)
    first = :mnesia.dirty_first(:redex)

    keyspace =
      keyspace(now, first, %{})
      |> Enum.map(fn {db, info} ->
        "db#{db}:keys=#{info.keys},expires=#{info.expires},avg_ttl=#{info.avg_ttl}\r\n"
      end)
      |> Enum.join()

    "# Keyspace\r\n#{keyspace}"
  end

  defp keyspace(_now, :"$end_of_table", acc), do: acc

  defp keyspace(now, key, acc) do
    next = :mnesia.dirty_next(:redex, key)

    acc =
      case :mnesia.dirty_read(:redex, key) do
        [{:redex, {db, _key}, _value, expiry}] when expiry > now ->
          acc = Map.put_new(acc, db, %{keys: 0, expires: 0, avg_ttl: 0})
          acc = update_in(acc[db].keys, &(&1 + 1))

          if expiry do
            ttl = expiry - now
            acc = update_in(acc[db].expires, &(&1 + 1))

            update_in(
              acc[db].avg_ttl,
              &trunc((&1 * (acc[db].expires - 1) + ttl) / acc[db].expires)
            )
          else
            acc
          end

        _ ->
          acc
      end

    keyspace(now, next, acc)
  end
end
