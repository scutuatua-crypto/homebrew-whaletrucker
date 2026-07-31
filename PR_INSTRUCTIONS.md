PREPARE RELEASE v0.1.0

This branch prepares the Homebrew formula changes for release v0.1.0.

What remains to complete:

1) Replace the placeholder SHA256 in Formula/scutua-mcp.rb with the actual tarball checksum:
   - Download the tarball:
     https://github.com/scutuatua-crypto/homebrew-whaletrucker/archive/refs/tags/v0.1.0.tar.gz
   - Compute checksum:
     shasum -a 256 /path/to/wt-v0.1.0.tar.gz
   - Replace REPLACE_WITH_TARBALL_SHA256 with the hex value and commit.

2) (Optional) Remove duplicate file in homebrew-core/Formula/scutua-mcp.rb if present.

3) Run audit locally or via CI: brew audit --strict Formula/scutua-mcp.rb

Notes for maintainers:
- This branch was created by the automation assistant to prepare the formula for v0.1.0 release.
- If you want the workflow to compute the SHA automatically, run the "Prepare Homebrew Release" workflow on branch v0.1.0 (Actions tab).
