defmodule FastHtml.Pool do
  @behaviour NimblePool
  @moduledoc """

  """

  require Logger

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Starts the port pool.

  ### Options
  - `:size` - Number of ports in the pool. Defaults to `System.schedulers_online/0` if not set.
  - `:name` - Registered name of the pool. Defaults to `#{__MODULE__}` if not set, set to `false` to not register the process.
  """
  @type option :: {:size, pos_integer()} | {:name, atom()}
  @spec start_link([option()]) :: term()
  def start_link(options) do
    {size, options} = Keyword.pop(options, :size, System.schedulers_online())
    NimblePool.start_link(worker: {__MODULE__, options}, pool_size: size)
  end

  @type pool :: atom() | pid()
  @type result :: {:ok, term()} | {:error, atom()}
  @spec get_port(pool(), (port() -> result())) :: result()
  def get_port(pool, fun) do
    NimblePool.checkout!(pool, :checkout, fn _from, port ->
      result = fun.(port)

      client_state =
        case result do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            reason
        end

      send(port, {self(), {:connect, GenServer.whereis(pool)}})

      client_state =
        receive do
          {^port, :connected} -> client_state
          {:EXIT, ^port, reason} -> {:EXIT, reason}
        end

      {result, client_state}
    end)
  end

  @impl NimblePool
  @doc false
  def init_pool(state) do
    {name, options} =
      case Keyword.pop(state, :name) do
        {nil, state} -> {__MODULE__, state}
        {name, state} when is_atom(name) -> {name, state}
        {_, state} -> {nil, state}
      end

    if name, do: Process.register(self(), name)
    {:ok, options}
  end

  @impl NimblePool
  @doc false
  def init_worker(pool_state) do
    port = :fast_html.open_port()
    {:ok, port, pool_state}
  end

  @impl NimblePool
  @doc false
  def terminate_worker({:EXIT, reason}, port, pool_state) do
    Logger.warn(fn ->
      "[#{__MODULE__}]: Port #{port} unexpectedly exited with reason: #{reason}"
    end)

    {:ok, pool_state}
  end

  @impl NimblePool
  @doc false
  def terminate_worker(_reason, port, pool_state) do
    Port.close(port)
    {:ok, pool_state}
  end

  @impl NimblePool
  @doc false
  def handle_checkout(:checkout, {client_pid, _}, port) do
    send(port, {self(), {:connect, client_pid}})

    receive do
      {^port, :connected} -> {:ok, port, port}
      {:EXIT, ^port, reason} -> {:remove, {:EXIT, reason}}
    end
  end

  @impl NimblePool
  @doc false
  def handle_checkin(:timeout, _, _), do: {:remove, :timeout}

  @impl NimblePool
  @doc false
  def handle_checkin(_, _, port), do: {:ok, port}

  @impl NimblePool
  @doc false
  def handle_info({:EXIT, port, reason}, port), do: {:remove, {:EXIT, reason}}

  @impl NimblePool
  @doc false
  def handle_info({:EXIT, _, _}, port), do: {:ok, port}

  # Port sent data to the pool, this happens when the timeout was reached
  # and the port got disconnected from the client, but not yet killed by the pool.
  # Just discard the message.
  @impl NimblePool
  @doc false
  def handle_info({_sending_port, {:data, _}}, port), do: {:ok, port}
end
