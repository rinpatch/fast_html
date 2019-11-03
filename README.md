# Myhtmlex

Bindings for lexborisov's [myhtml](https://github.com/lexborisov/myhtml).

* Available as a hex package: `{:myhtmlex, "~> 0.2.0"}`
* [Documentation](https://hexdocs.pm/myhtmlex/Myhtmlex.html)

## Example

    iex> Myhtmlex.decode("<h1>Hello world</h1>")
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

## Contribution / Bug Reports

* Please make sure you do `git submodule update` after a checkout/pull
* If you have problems building the project, please consider adding a Dockerfile to `build-tests/` to replicate the build error
* The project aims to be fully tested

## Roadmap

The exposed functions on `Myhtmlex` are not subject to change.
This project is under active development.

* [ ] Expose node-retrieval functions
* [x] Parse a HTML-document into a tree
* [x] Investigate safety and calling options
  * [x] Call as dirty-nif
  * [x] Call as C-Node (check branch `c-node`)

