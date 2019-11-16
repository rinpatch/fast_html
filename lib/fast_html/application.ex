defmodule FastHtml.Application do
  @moduledoc false

  use Application

  def random_sname, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  def start(_type, _args) do
    case maybe_setup_node() do
      {:error, message} -> raise message
      _ -> :ok
    end

    Supervisor.start_link([{FastHtml.Cnode, Application.get_env(:fast_html, :cnode, [])}],
      strategy: :one_for_one,
      name: FastHtml.Supervisor
    )
  end

  defp maybe_setup_node() do
    with {_, false} <- {:alive, Node.alive?()},
         {:ok, epmd_path} <- find_epmd(),
         :ok <- start_epmd(epmd_path),
         {:ok, _pid} = pid_tuple <- start_node() do
      pid_tuple
    else
      {:alive, _} ->
        :ok

      {:error, _} = e ->
        e
    end
  end

  defp find_epmd() do
    case System.find_executable("epmd") do
      nil ->
        {:error,
         "Could not find epmd executable. Please ensure the location it's in is present in your PATH or start epmd manually beforehand"}

      executable ->
        {:ok, executable}
    end
  end

  defp start_epmd(path) do
    case System.cmd(path, ["-daemon"]) do
      {_result, 0} -> :ok
      {_result, exit_code} -> {:error, "Could not start epmd, exit code: #{exit_code}"}
    end
  end

  defp start_node() do
    Node.start(:"master_#{random_sname()}@127.0.0.1")
  end
end
