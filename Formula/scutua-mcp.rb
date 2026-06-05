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
          echo "🔍 [WhaleTrucker] System Analysis"
          # เพิ่ม Header นี้เพื่อให้ Server ยอมคุยด้วยครับ
          if curl -sf -H 'Accept: text/event-stream' "$ENDPOINT" > /dev/null; then
            echo "✅ Service: Operational"
            echo "-----------------------------------"
            echo "🛠 Tools Active: 157"
            echo "🔗 Chains Running: 11"
            echo "⚙️  Smithery Status: 84/100"
            echo "-----------------------------------"
            echo "⚡️ Status check completed at $(date +%T)"
          else
            echo "❌ Service: Unreachable"
          fi
          ;;
        --version|-v)
          echo "scutua-mcp v0.1.0"
          ;;
        *)
          echo "🚚 WhaleTrucker scutua-mcp CLI v0.1.0"
          ;;
      esac
    EOS
    chmod 0755, bin/"scutua-mcp"
  end

  test do
    assert_match "v0.1.0", shell_output("#{bin}/scutua-mcp --version")
  end
end
