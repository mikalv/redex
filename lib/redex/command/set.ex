defmodule Redex.Command.SET do
  use Redex.Command

  @default_args %{expiry: nil, nx: false, xx: false}

  def exec([key, value | args], state = state(quorum: quorum, db: db)) do
    case args(args, @default_args) do
      {:ok, args} ->
        nodes = :mnesia.system_info(:running_db_nodes)

        cond do
          length(nodes) < quorum ->
            {:error, "READONLY You can't write against a read only replica."}

          length(nodes) == 1 ->
            :ok = :mnesia.dirty_write({:redex, {db, key}, value, args.expiry})

          true ->
            {:atomic, :ok} =
              :mnesia.sync_transaction(fn ->
                :mnesia.write({:redex, {db, key}, value, args.expiry})
              end)

            :ok
        end

      error ->
        error
    end
    |> reply(state)
  end

  def exec(_, state), do: wrong_arg_error("SET") |> reply(state)

  def args([], acc), do: {:ok, acc}

  def args([ex, arg | rest], acc = %{expiry: nil}) when ex in ["ex", "EX", "eX", "Ex"] do
    args(rest, %{acc | expiry: System.system_time(:millisecond) + String.to_integer(arg) * 1000})
  end

  def args([px, arg | rest], acc = %{expiry: nil}) when px in ["px", "PX", "pX", "Px"] do
    args(rest, %{acc | expiry: System.system_time(:millisecond) + String.to_integer(arg)})
  end

  def args([nx | rest], acc = %{xx: false}) when nx in ["nx", "NX", "nX", "Nx"] do
    args(rest, %{acc | nx: true})
  end

  def args([xx | rest], acc = %{nx: false}) when xx in ["xx", "XX", "xX", "Xx"] do
    args(rest, %{acc | xx: true})
  end

  def args(_args, _acc), do: {:error, "ERR syntax error"}
end
