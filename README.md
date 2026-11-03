# bruce-fedora-docs-ci

The dev deployment of [`bruce`](https://github.com/mwinters0/bruce)'s
[deployment guide](https://github.com/mwinters0/bruce/blob/main/docs/manual/deploy.md):
a nightly crawl of docs.fedoraproject.org's en-US, published on this repo's GitHub
Pages from the `gh-pages` branch, which holds one commit, force-pushed each night.

- `bruce.toml` and `bruce-nightly.sh` are the guide's, copied from it.
- `.github/workflows/nightly.yml` runs the script on the `bruce` release it pins
  (`BRUCE_TAG`), keeping no history.
  It keeps 30 nights of digest JSON (`KEEP_JSON`), as long as its other views, where
  the guide's default is 90.

Published at https://mwinters0.github.io/bruce-fedora-docs-ci/.
