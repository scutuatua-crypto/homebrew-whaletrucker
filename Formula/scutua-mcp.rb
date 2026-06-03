class ScutuaMcp < Formula
  desc "WhaleTrucker scutua-mcp — 157 DeFi tools via MCP"
  homepage "https://whaletrucker-ecosystem.pages.dev"
  url "https://github.com/scutuatua-crypto/homebrew-whaletrucker/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "81bd173716cca0642a4b3f31b21348809412781fb224fde31731a493b0cf81b7"
  version "0.1.0"
  license "MIT"

  def install
    (bin/"scutua-mcp").write <<~EOS
      #!/bin/bash
      ENDPOINT="https://scutua-mcp.onrender.com/mcp"
      CONFIG_CLAUDE="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
      CONFIG_CURSOR="$HOME/.cursor/mcp.json"
      case "$1" in
        config)
          JSON='{"mcpServers":{"scutua-mcp":{"url":"'$ENDPOINT'"}}}'
          if [ "$2" = "cursor" ]; then
            mkdir -p "$(dirname "$CONFIG_CURSOR")"
            echo "$JSON" > "$CONFIG_CURSOR"
            echo "✅ Cursor config written → $CONFIG_CURSOR"
          else
            mkdir -p "$(dirname "$CONFIG_CLAUDE")"
            echo "$JSON" > "$CONFIG_CLAUDE"
            echo "✅ Claude Desktop config written → $CONFIG_CLAUDE"
          fi
          ;;
        status)
          CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT")
          if [ "$CODE" = "200" ] || [ "$CODE" = "307" ]; then
            echo "✅ Online (HTTP $CODE)"
          else
            echo "⚠️  HTTP $CODE — Render cold starting..."
          fi
          ;;
        *)
          echo "🚚 WhaleTrucker scutua-mcp v0.1.0"
          echo ""
          echo "Commands:"
          echo "  scutua-mcp config          → Claude Desktop config"
          echo "  scutua-mcp config cursor   → Cursor config"
          echo "  scutua-mcp status          → check endpoint"
          echo ""
          echo "Endpoint: $ENDPOINT"
          echo "Tools: 157 | Chains: 11 | Smithery: 84/100"
          ;;
      esac
    EOS
    chmod 0755, bin/"scutua-mcp"
  end

  test do
    assert_match "WhaleTrucker", shell_output("#{bin}/scutua-mcp")
  end
end
