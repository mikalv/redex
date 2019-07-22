defmodule Redex.Command.RPUSH do
  use Redex.Command

  def exec([key | values], state = %State{quorum: quorum, db: db}) when values != [] do
    if readonly?(quorum) do
      {:error, "READONLY You can't write against a read only replica."}
    else
      now = System.os_time(:millisecond)

      {:atomic, result} =
        Mnesia.sync_transaction(fn ->
          case Mnesia.read(:redex, {db, key}, :write) do
            [{:redex, {^db, ^key}, list, expiry}] when expiry > now and is_list(list) ->
              {list ++ values, expiry}

            [{:redex, {^db, ^key}, _value, expiry}] when expiry > now ->
              {:error, "WRONGTYPE Operation against a key holding the wrong kind of value"}

            _ ->
              {values, nil}
          end
          |> case do
            {:error, error} ->
              {:error, error}

            {values, expiry} ->
              Mnesia.write({:redex, {db, key}, values, expiry})
              length(values)
          end
        end)

      result
    end
    |> reply(state)
  end

  def exec(_, state), do: wrong_arg_error("RPUSH") |> reply(state)
end
