class ScutuaMcp < Formula
  desc "CLI wrapper for the WhaleTrucker scutua-mcp DeFi server — 157 tools · 8 dimensions"
  homepage "https://whaletrucker-ecosystem.pages.dev"
  url "https://github.com/scutuatua-crypto/scutua-mcp/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "eb5bd7250852f33a973a213f77d9179c2f51b46a3b69d9d10e33ae689a2f4cb6"
  license "MIT"

  def install
    (bin/"scutua-mcp").write <<~EOS
      #!/bin/bash
      ENDPOINT="https://scutua-mcp.onrender.com/mcp"

      case "$1" in
        status)
          echo "🔍 [WhaleTrucker] scutua-mcp — 157 tools · 8 dimensions"
          HTTP_CODE=$(curl -s -o /dev/null --max-time 10 -w "%{http_code}" "$ENDPOINT")
          if echo "$HTTP_CODE" | grep -qE "^(200|404|406)"; then
            echo "✅ Service: Live"
            echo "-----------------------------------"
            echo "🌐 Endpoint: $ENDPOINT"
            echo "🛠  Tools: 157 across 8 dimensions"
            echo "-----------------------------------"
            echo "⚡️ Status check completed at $(date +%T)"
          else
            echo "❌ Service: Unreachable"
          fi
          ;;
        *)
          echo "🚚 WhaleTrucker scutua-mcp CLI"
          echo "Connect via: $ENDPOINT"
          echo "Run 'scutua-mcp status' to check service health"
          ;;
      esac
    EOS
    (bin/"scutua-mcp").chmod 0755
  end

  test do
    system "#{bin}/scutua-mcp"
  end
end
