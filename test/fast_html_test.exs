defmodule :fast_html_test do
  use ExUnit.Case
  doctest :fast_html

  test "doesn't segfault when <!----> is encountered" do
    assert {:ok, {"html", _attrs, _children}} = :fast_html.decode("<div> <!----> </div>")
  end

  test "builds a tree, formatted like mochiweb by default" do
    assert {:ok,
            {"html", [],
             [
               {"head", [], []},
               {"body", [],
                [
                  {"br", [], []}
                ]}
             ]}} = :fast_html.decode("<br>")
  end

  test "builds a tree, html tags as atoms" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {:br, [], []}
                ]}
             ]}} = :fast_html.decode("<br>", format: [:html_atoms])
  end

  test "builds a tree, nil self closing" do
    assert {:ok,
            {"html", [],
             [
               {"head", [], []},
               {"body", [],
                [
                  {"br", [], nil},
                  {"esi:include", [], nil}
                ]}
             ]}} = :fast_html.decode("<br><esi:include />", format: [:nil_self_closing])
  end

  test "builds a tree, multiple format options" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {:br, [], nil}
                ]}
             ]}} = :fast_html.decode("<br>", format: [:html_atoms, :nil_self_closing])
  end

  test "attributes" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {:span, [{"id", "test"}, {"class", "foo garble"}], []}
                ]}
             ]}} =
             :fast_html.decode(~s'<span id="test" class="foo garble"></span>',
               format: [:html_atoms]
             )
  end

  test "single attributes" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {:button, [{"disabled", "disabled"}, {"class", "foo garble"}], []}
                ]}
             ]}} =
             :fast_html.decode(~s'<button disabled class="foo garble"></span>',
               format: [:html_atoms]
             )
  end

  test "text nodes" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  "text node"
                ]}
             ]}} = :fast_html.decode(~s'<body>text node</body>', format: [:html_atoms])
  end

  test "broken input" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {:a, [{"<", "<"}], [" asdf"]}
                ]}
             ]}} = :fast_html.decode(~s'<a <> asdf', format: [:html_atoms])
  end

  test "namespaced tags" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {"svg:svg", [],
                   [
                     {"svg:path", [], []},
                     {"svg:a", [], []}
                   ]}
                ]}
             ]}} = :fast_html.decode(~s'<svg><path></path><a></a></svg>', format: [:html_atoms])
  end

  test "custom namespaced tags" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  {"esi:include", [], nil}
                ]}
             ]}} =
             :fast_html.decode(~s'<esi:include />', format: [:html_atoms, :nil_self_closing])
  end

  test "html comments" do
    assert {:ok,
            {:html, [],
             [
               {:head, [], []},
               {:body, [],
                [
                  comment: " a comment "
                ]}
             ]}} = :fast_html.decode(~s'<body><!-- a comment --></body>', format: [:html_atoms])
  end
end