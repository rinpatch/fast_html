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
  * `timeout` - Call timeout
  * `format` - Format flags for the tree

  The following format flags are available:

  * `:html_atoms` uses atoms for known html tags (faster), binaries for everything else.
  * `:nil_self_closing` uses `nil` to designate self-closing tags and void elements.
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
        {:body, [], [{:comment, [], " a comment "}, {"unknown", [], nil}]}]}]}

  """
  @spec decode(String.t(), format: [format_flag()]) ::
          {:ok, tree()} | {:error, String.t() | atom()}
  def decode(bin, opts \\ []) do
    flags = Keyword.get(opts, :format, [])
    timeout = Keyword.get(opts, :timeout, 10000)
    FastHtml.Cnode.call({:decode, bin, flags}, timeout)
  end
end
