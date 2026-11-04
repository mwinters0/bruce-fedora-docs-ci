# bruce-fedora-docs-ci

The dev deployment of [`bruce`](https://github.com/mwinters0/bruce)'s
[deployment guide](https://github.com/mwinters0/bruce/blob/main/docs/manual/deploy.md):
a nightly crawl of docs.fedoraproject.org's en-US, published on this repo's GitHub
Pages from the `gh-pages` branch, which holds one commit, force-pushed each night.

- `bruce.toml`, `bruce-nightly.sh` and `fedora.html`, the digest's view, are the guide's, copied from it
  (`bruce.toml` differs in its User-Agent). The view's digest is published as `digest.html`, as the built-in view's would be.
- `.github/workflows/nightly.yml` runs the script on the `bruce` release it pins
  (`BRUCE_TAG`), keeping no history.
  It keeps 30 nights of digest JSON (`KEEP_JSON`), as long as its other views, where
  the guide's default is 90.
  It sets `INDEX`, so the Pages root is `index.html`, a page linking the latest files and each night's digests.

Published at https://mwinters0.github.io/bruce-fedora-docs-ci/.
