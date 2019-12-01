# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.0] - 2019-12-01
### Changed
- **BREAKING:** `:fast_html.decode` now returns an array of nodes at the top level, instead of a single node. This was done because it's possible to have more than one root node, for example in (`<!-- a comment --> <html> </html>` both the comment and the `html` tag are root nodes).

### Fixed
- Worker going into infinite loop when decoding a document with more than one root node.
