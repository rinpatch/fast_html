defmodule BasicHtmlBench do
  use Benchfella

  bench "decode" do
    {html, _} = bench_context
    :fast_html.decode(html)
  end

  bench "decode w/ html_atoms" do
    {html, _} = bench_context
    :fast_html.decode(html, format: [:html_atoms])
  end

  bench "decode w/ nil_self_closing" do
    {html, _} = bench_context
    :fast_html.decode(html, format: [:nil_self_closing])
  end

  bench "decode w/ html_atoms, nil_self_closing" do
    {html, _} = bench_context
    :fast_html.decode(html, format: [:html_atoms, :nil_self_closing])
  end
end
