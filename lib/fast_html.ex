defmodule :fast_html do
  @moduledoc """
  A module to decode html into a tree structure.

  Based on [Alexander Borisov's myhtml](https://github.com/lexborisov/myhtml),
  this binding gains the properties of being html-spec compliant and very fast.

  ## Example

      iex> :fast_html.decode("<h1>Hello world</h1>")
      {"html", [], [{"head", [], []}, {"body", [], [{"h1", [], ["Hello world"]}]}]}

  Benchmark results (removed Nif calling mode) on various file sizes on a 2,5Ghz Core i7:

      Settings:
        duration:      1.0 s

      ## FileSizesBench
      [15:28:42] 1/3: github_trending_js.html 341k
      [15:28:46] 2/3: w3c_html5.html 131k
      [15:28:48] 3/3: wikipedia_hyperlink.html 97k

      Finished in 7.52 seconds

      ## FileSizesBench
      benchmark name                iterations   average time
      wikipedia_hyperlink.html 97k        1000   1385.86 µs/op
      w3c_html5.html 131k                 1000   2179.30 µs/op
      github_trending_js.html 341k         500   5686.21 µs/op
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

  ## Examples

      iex> :fast_html.decode("<h1>Hello world</h1>")
      {"html", [], [{"head", [], []}, {"body", [], [{"h1", [], ["Hello world"]}]}]}

      iex> :fast_html.decode("<span class='hello'>Hi there</span>")
      {"html", [],
       [{"head", [], []},
        {"body", [], [{"span", [{"class", "hello"}], ["Hi there"]}]}]}

      iex> :fast_html.decode("<body><!-- a comment --!></body>")
      {"html", [], [{"head", [], []}, {"body", [], [comment: " a comment "]}]}

      iex> :fast_html.decode("<br>")
      {"html", [], [{"head", [], []}, {"body", [], [{"br", [], []}]}]}
  """
  @spec decode(String.t()) :: tree()
  def decode(bin) do
    decode(bin, format: [])
  end

  @doc """
  Returns a tree representation from the given html string.

  This variant allows you to pass in one or more of the following format flags:

  * `:html_atoms` uses atoms for known html tags (faster), binaries for everything else.
  * `:nil_self_closing` uses `nil` to designate self-closing tags and void elements.
      For example `<br>` is then being represented like `{"br", [], nil}`.
      See http://w3c.github.io/html-reference/syntax.html#void-elements for a full list of void elements.
  * `:comment_tuple3` uses 3-tuple elements for comments, instead of the default 2-tuple element.

  ## Examples

      iex> :fast_html.decode("<h1>Hello world</h1>", format: [:html_atoms])
      {:html, [], [{:head, [], []}, {:body, [], [{:h1, [], ["Hello world"]}]}]}

      iex> :fast_html.decode("<br>", format: [:nil_self_closing])
      {"html", [], [{"head", [], []}, {"body", [], [{"br", [], nil}]}]}

      iex> :fast_html.decode("<body><!-- a comment --!></body>", format: [:comment_tuple3])
      {"html", [], [{"head", [], []}, {"body", [], [{:comment, [], " a comment "}]}]}

      iex> html = "<body><!-- a comment --!><unknown /></body>"
      iex> :fast_html.decode(html, format: [:html_atoms, :nil_self_closing, :comment_tuple3])
      {:html, [],
       [{:head, [], []},
        {:body, [], [{:comment, [], " a comment "}, {"unknown", [], nil}]}]}

  """
  @spec decode(String.t(), format: [format_flag()]) :: tree()
  def decode(bin, format: flags) do
    {:ok, {:myhtml_worker, res}} = Nodex.Cnode.call(FastHtml.Cnode, {:decode, bin, flags})
    res
  end
end
