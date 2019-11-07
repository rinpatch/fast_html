# FastHTML

A C Node wrapping lexborisov's [myhtml](https://github.com/lexborisov/myhtml).
Primarily used with [FastSanitize](https://git.pleroma.social/pleroma/fast_sanitize).

* Available as a hex package: `{:fast_html, "~> 0.99"}`
* [Documentation](https://hexdocs.pm/fast_html/fast_html.html)

## Benchmarks

The following table provides median times it takes to decode a string to a tree for html parsers that can be used from Elixir. Benchmarks were conducted on a machine with `Intel Core i7-3520M @ 2.90GHz` CPU and 16GB of RAM. The `mix fast_html.bench` task can be used for running the benchmark by yourself.

| File/Parser          | fast_html (C-Node) | mochiweb_html (erlang) | html5ever (Rust NIF) | Myhtmlex (NIF)¹ |
|----------------------|--------------------|------------------------|----------------------|----------------|
| document-large.html  | 178.13 ms          | 3471.70 ms             | 799.20 ms            | 402.64 ms      |
| document-medium.html | 2.85 ms            | 26.58 ms               | 9.06 ms              | 3.72 ms        |
| document-small.html  | 1.08 ms            | 5.45 ms                | 2.10 ms              | 1.24 ms        |
| fragment-large.html  | 1.50 ms            | 10.91 ms               | 6.03 ms              | 1.91 ms        |
| fragment-small.html²  | 434.64 μs          | 83.02 μs               | 57.97 μs             | 311.39 μs      |

1. Myhtmlex has a C-Node mode as well, but it wasn't benchmarked here because it segfaults on `document-large.html`
2. The slowdown on `fragment-small.html` is due to C-Node overhead. Unlike html5ever and Myhtmlex in NIF mode, `fast_html` has the parser process isolated and communicates with it over the network, so even if a fatal crash in the parser happens, it won't bring down the entire VM.
## Contribution / Bug Reports

* Please make sure you do `git submodule update` after a checkout/pull
* The project aims to be fully tested
