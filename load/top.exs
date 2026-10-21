# SPDX-FileCopyrightText: 2026 Mariano Pictet and contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Where the server spends its time during a load test: the processes that did the most work
# (reductions) over 5 seconds, grouped by what they are, with a sample of where the busiest
# ones are. Run inside the app: bin/idejo rpc 'Code.eval_file("/load/top.exs")'

kind = fn pid ->
  case Process.info(pid, [:dictionary, :initial_call, :registered_name]) do
    nil ->
      :gone

    info ->
      cond do
        info[:registered_name] not in [nil, []] -> info[:registered_name]
        mfa = info[:dictionary][:"$initial_call"] -> mfa
        true -> info[:initial_call]
      end
  end
end

before = Map.new(Process.list(), &{&1, elem(Process.info(&1, :reductions) || {:r, 0}, 1)})
Process.sleep(5_000)

deltas =
  for pid <- Process.list(), r = Process.info(pid, :reductions), r != nil do
    {pid, elem(r, 1) - Map.get(before, pid, 0)}
  end

total = deltas |> Enum.map(&elem(&1, 1)) |> Enum.sum()

deltas
|> Enum.group_by(fn {pid, _} -> kind.(pid) end, &elem(&1, 1))
|> Enum.map(fn {k, rs} -> {k, Enum.sum(rs), length(rs)} end)
|> Enum.sort_by(&elem(&1, 1), :desc)
|> Enum.take(12)
|> Enum.each(fn {k, r, n} ->
  IO.puts(
    "#{String.pad_leading(Float.to_string(Float.round(100 * r / total, 1)), 5)}%  #{n} × #{inspect(k)}"
  )
end)

IO.puts("\nWhere the busiest processes are (10 samples each of the top 3):")

deltas
|> Enum.sort_by(&elem(&1, 1), :desc)
|> Enum.take(3)
|> Enum.each(fn {pid, _} ->
  samples =
    for _ <- 1..10, st = Process.info(pid, :current_stacktrace), st != nil do
      Process.sleep(50)

      st
      |> elem(1)
      |> Enum.take(4)
      |> Enum.map_join(" < ", fn {m, f, a, _} -> "#{inspect(m)}.#{f}/#{a}" end)
    end

  IO.puts("#{inspect(kind.(pid))}:")

  samples
  |> Enum.frequencies()
  |> Enum.sort_by(&elem(&1, 1), :desc)
  |> Enum.take(3)
  |> Enum.each(fn {s, n} -> IO.puts("  #{n}× #{s}") end)
end)
