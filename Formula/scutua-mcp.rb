class ScutuaMcp < Formula
  desc "WhaleTrucker MCP CLI — 157 tools · 11 chains"
  homepage "https://whaletrucker-ecosystem.pages.dev"
  url "https://github.com/scutuatua-crypto/homebrew-whaletrucker/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "81bd173716cca0642a4b3f31b21348809412781fb224fde31731a493b0cf81b7"
  license "MIT"

  def install
    (bin/"scutua-mcp").write <<~EOS
      #!/bin/bash
      ENDPOINT="https://scutua-mcp.onrender.com/mcp"

      case "$1" in
        config)
          if [ "$2" = "cursor" ]; then
            CONFIG_FILE="$HOME/.cursor/mcp.json"
          else
            CONFIG_FILE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
          fi
          mkdir -p "$(dirname "$CONFIG_FILE")"
          cat > "$CONFIG_FILE" <<JSON
      {
        "mcpServers": {
          "scutua-mcp": {
            "type": "sse",
            "url": "$ENDPOINT"
          }
        }
      }
      JSON
          echo "✅ Config written to $CONFIG_FILE"
          ;;
        status)
          echo "🔍 Checking $ENDPOINT ..."
          curl -sf "$ENDPOINT" > /dev/null && echo "✅ Endpoint is live" || echo "❌ Endpoint unreachable"
          ;;
        --version|-v)
          echo "scutua-mcp v0.1.0"
          ;;
        *)
          echo "🚚 WhaleTrucker scutua-mcp CLI v0.1.0"
          echo ""
          echo "Usage:"
          echo "  scutua-mcp config          — write Claude Desktop config"
          echo "  scutua-mcp config cursor   — write Cursor config"
          echo "  scutua-mcp status          — check endpoint health"
          echo "  scutua-mcp --version       — show version"
          echo ""
          echo "Endpoint: $ENDPOINT"
          echo "Tools: 157 · Chains: 11"
          ;;
      esac
    EOS
    chmod 0755, bin/"scutua-mcp"
  end

  test do
    assert_match "v0.1.0", shell_output("#{bin}/scutua-mcp --version")
  end
end
