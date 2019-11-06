defmodule FastHtml.Cnode do
  @moduledoc false

  @spawn_inactive_timeout 10000

  application = Mix.Project.config()[:app]

  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    args =
      if args == [] do
        %{}
      else
        args
      end

    exec_path = Path.join(:code.priv_dir(unquote(application)), "myhtml_worker")

    sname = Map.get_lazy(args, :sname, &default_sname/0)
    hostname = Map.get_lazy(args, :hostname, &master_hostname/0)
    addr = :"#{sname}@#{hostname}"

    spawn_inactive_timeout = Map.get(args, :spawn_inactive_timeout, @spawn_inactive_timeout)

    state = %{
      exec_path: exec_path,
      sname: sname,
      addr: addr,
      hostname: hostname,
      spawn_inactive_timeout: spawn_inactive_timeout
    }

    connect_or_spawn_cnode(state)
  end

  defp default_sname, do: "myhtml_#{FastHtml.Application.random_sname()}"
  defp master_sname, do: Node.self() |> to_string |> String.split("@") |> List.first()
  defp master_hostname, do: Node.self() |> to_string |> String.split("@") |> List.last()

  defp connect_or_spawn_cnode(state) do
    case connect_cnode(state) do
      {:stop, _} -> spawn_cnode(state)
      {:ok, state} -> state
    end
  end

  defp connect_cnode(%{addr: addr} = state) do
    if Node.connect(addr) do
      Logger.debug("connected to #{addr}")
      {:ok, state}
    else
      Logger.debug("connecting to #{addr} failed")
      {:stop, :cnode_connection_fail}
    end
  end

  defp spawn_cnode(%{exec_path: exec_path, sname: sname, hostname: hostname} = state) do
    Logger.debug("Spawning #{sname}@#{hostname}")

    cookie = :erlang.get_cookie()

    port =
      Port.open({:spawn_executable, exec_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        line: 4096,
        args: [sname, hostname, cookie, master_sname()]
      ])

    pid = Keyword.get(Port.info(port), :os_pid)
    state = Map.put(state, :pid, pid)
    await_cnode_ready(port, state)
  end

  defp await_cnode_ready(
         port,
         %{spawn_inactive_timeout: timeout, addr: addr} = state
       ) do
    ready_line = to_string(addr) <> " ready"

    receive do
      {^port, {:data, {:eol, ^ready_line}}} ->
        connect_cnode(state)

      {^port, {:data, {:eol, line}}} ->
        Logger.debug("c-node is saying: #{line}")
        await_cnode_ready(port, state)

      {^port, {:exit_status, exit_status}} ->
        Logger.debug("unexpected c-node exit: #{exit_status}")
        {:stop, :cnode_unexpected_exit}

      message ->
        Logger.warn("unhandled message while waiting for cnode to be ready:\n#{inspect(message)}")
        await_cnode_ready(port, state)
    after
      timeout ->
        {:stop, :spawn_inactive_timeout}
    end
  end

  def handle_info({:nodedown, _cnode}, state) do
    {:stop, :nodedown, state}
  end

  def handle_info(msg, state) do
    Logger.warn("unhandled handle_info: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_call(:addr, _from, %{addr: addr} = state) do
    {:reply, addr, state}
  end

  def terminate(_reason, %{pid: pid}) when pid != nil do
    System.cmd("kill", ["-9", to_string(pid)])
    :normal
  end

  def call(msg, timeout \\ 10000) do
    node = GenServer.call(__MODULE__, :addr)
    send({nil, node}, msg)

    receive do
      {:myhtml_worker, res} -> {:ok, res}
    after
      timeout -> {:error, :timeout}
    end
  end
end
