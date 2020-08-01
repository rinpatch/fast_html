defmodule :fast_html do
  @moduledoc """
  A module to decode html into a tree structure.
  """

  @type tag() :: String.t() | atom()
  @type attr() :: {String.t(), String.t()}
  @type attr_list() :: [] | [attr()]
  @type comment_node() :: {:comment, String.t()}
  @type comment_node3() :: {:comment, [], String.t()}
  @type tree() ::
          {tag(), attr_list(), tree()}
          | {tag(), attr_list(), nil}
          | comment_node()
          | comment_node3()
  @type format_flag() :: :html_atoms | :nil_self_closing | :comment_tuple3

  @doc """
  Returns a tree representation from the given html string.

  `opts` is a keyword list of options, the options available:
  * `timeout` - Call timeout. If pooling is used and the worker doesn't return
     the result in time, the worker will be killed with a warning.
  * `format` - Format flags for the tree.

  The following format flags are available:

  * `:html_atoms` uses atoms for known html tags (faster), binaries for everything else.
  * `:nil_self_closing` uses `nil` to designate void elements.
      For example `<br>` is then being represented like `{"br", [], nil}`.
      See http://w3c.github.io/html-reference/syntax.html#void-elements for a full list of void elements.
  * `:comment_tuple3` uses 3-tuple elements for comments, instead of the default 2-tuple element.

  ## Examples
      iex> :fast_html.decode("<h1>Hello world</h1>")
      {:ok, [{"html", [], [{"head", [], []}, {"body", [], [{"h1", [], ["Hello world"]}]}]}]}

      iex> :fast_html.decode("Hello world", timeout: 0)
      {:error, :timeout}

      iex> :fast_html.decode("<span class='hello'>Hi there</span>")
      {:ok, [{"html", [],
       [{"head", [], []},
        {"body", [], [{"span", [{"class", "hello"}], ["Hi there"]}]}]}]}

      iex> :fast_html.decode("<body><!-- a comment --!></body>")
      {:ok, [{"html", [], [{"head", [], []}, {"body", [], [comment: " a comment "]}]}]}

      iex> :fast_html.decode("<br>")
      {:ok, [{"html", [], [{"head", [], []}, {"body", [], [{"br", [], []}]}]}]}

      iex> :fast_html.decode("<h1>Hello world</h1>", format: [:html_atoms])
      {:ok, [{:html, [], [{:head, [], []}, {:body, [], [{:h1, [], ["Hello world"]}]}]}]}

      iex> :fast_html.decode("<br>", format: [:nil_self_closing])
      {:ok, [{"html", [], [{"head", [], []}, {"body", [], [{"br", [], nil}]}]}]}

      iex> :fast_html.decode("<body><!-- a comment --!></body>", format: [:comment_tuple3])
      {:ok, [{"html", [], [{"head", [], []}, {"body", [], [{:comment, [], " a comment "}]}]}]}

      iex> html = "<body><!-- a comment --!><unknown /></body>"
      iex> :fast_html.decode(html, format: [:html_atoms, :nil_self_closing, :comment_tuple3])
      {:ok, [{:html, [],
       [{:head, [], []},
        {:body, [], [{:comment, [], " a comment "}, {"unknown", [], []}]}]}]}

  """
  @spec decode(String.t(), format: [format_flag()]) ::
          {:ok, tree()} | {:error, String.t() | atom()}
  def decode(bin, opts \\ []) do
    flags = Keyword.get(opts, :format, [])
    timeout = Keyword.get(opts, :timeout, 10000)

    find_and_use_port({:decode, bin, flags}, timeout, opts)
  end

  @doc """
  Like `decode/2`, but for parsing [HTML fragments](https://html.spec.whatwg.org/multipage/parsing.html#parsing-html-fragments).

  `opts` is a keyword list of options, the options available are the same as in `decode/2` with addition of:
  * `context` - Name of the context element, defaults to `div`

  Example:
      iex> :fast_html.decode_fragment("rin is the <i>best</i> girl")
      {:ok, ["rin is the ", {"i", [], ["best"]}, " girl"]}
      iex> :fast_html.decode_fragment("rin is the <i>best</i> girl", context: "title")
      {:ok, ["rin is the <i>best</i> girl"]}
      iex> :fast_html.decode_fragment("rin is the <i>best</i> girl", context: "objective_truth")
      {:error, :unknown_context_tag}
      iex> :fast_html.decode_fragment("rin is the <i>best</i> girl", format: [:html_atoms])
      {:ok, ["rin is the ", {:i, [], ["best"]}, " girl"]}
  """
  def decode_fragment(bin, opts \\ []) do
    flags = Keyword.get(opts, :format, [])
    timeout = Keyword.get(opts, :timeout, 10000)
    context = Keyword.get(opts, :context, "div")

    find_and_use_port({:decode_fragment, bin, flags, context}, timeout, opts)
  end

  @default_pool FastHtml.Pool
  defp find_and_use_port(term_command, timeout, opts) do
    command = :erlang.term_to_binary(term_command)

    pool =
      cond do
        pool = Keyword.get(opts, :pool) -> pool
        Application.get_env(:fast_html, :pool, enabled: true)[:enabled] -> @default_pool
        true -> nil
      end

    execute_command_fun = fn port ->
      send(port, {self(), {:command, command}})

      receive do
        {^port, {:data, res}} -> {:ok, res}
      after
        timeout ->
          {:error, :timeout}
      end
    end

    result =
      if pool do
        FastHtml.Pool.get_port(pool, execute_command_fun)
      else
        port = open_port()
        result = execute_command_fun.(port)
        Port.close(port)
        result
      end

    case result do
      {:ok, result} -> :erlang.binary_to_term(result)
      {:error, _} = e -> e
    end
  end

  def open_port do
    Port.open({:spawn_executable, Path.join([:code.priv_dir(:fast_html), "fasthtml_worker"])}, [
      :binary,
      {:packet, 4},
      :use_stdio,
      :exit_status
    ])
  end
end
