# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.0.0] - 2020-08-01
### Changed
- **Breaking:** CMake is now required at compile-time due to it being lexbor's build system
- **Breaking:** namespaces are no longer automatically appended. i.e "<svg> </svg>" will be `{"svg", [], []}` instead of `{"svg:svg", [], []}`
- **Breaking:** when using `:nil_self_closing` flag, only valid [void elements](https://html.spec.whatwg.org/#void-elements) will have `nil` in children
- Now deprecated myhtml was switched to [lexbor](https://github.com/lexbor/lexbor)
- The worker process now communicates with the node via stdio, instead of TCP, which was known to cause issues
on BSD systems 

### Added
- `FastHtml.Pool` for fast_html workers. There is a default pool of `System.schedulers_online/0` workers, but a custom pool can be started if desired, or it can be disabled altogether. See `FastHtml.Pool` module documentation for more info

## [1.0.3] - 2020-02-10
### Fixed
- C-Node not respawning after being killed.

## [1.0.2] - 2020-02-10
### Fixed
- Incorrect behavior when parsing empty attribute values. Instead of an empty string the attribute name was returned.

## [1.0.1] - 2019-12-11
### Added
- `:fast_html.decode_fragment`
### Fixed
- Errors from C-Node not being reported, timing out instead

## [1.0.0] - 2019-12-02
### Changed
- **BREAKING:** `:fast_html.decode` now returns an array of nodes at the top level, instead of a single node. This was done because it's possible to have more than one root node, for example in (`<!-- a comment --> <html> </html>` both the comment and the `html` tag are root nodes).

### Fixed
- Worker going into infinite loop when decoding a document with more than one root node.
