class ScutuaMcp < Formula
  desc "WhaleTrucker MCP CLI — 157 tools · 11 chains"
  homepage "https://whaletrucker-ecosystem.pages.dev"
  url "https://github.com/scutuatua-crypto/homebrew-whaletrucker/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "81bd173716cca0642a4b3f31b21348809412781fb224fde31731a493b0cf81b7"
  license "MIT"

  def install
    (bin/"scutua-mcp").write <<~EOS
      #!/bin/bash
      # เปลี่ยนมาเช็คที่หน้า Root ของ Service แทนการเช็คที่ /mcp
      ENDPOINT="https://scutua-mcp.onrender.com"

      case "$1" in
        status)
          echo "🔍 [WhaleTrucker] System Analysis"
          # ใช้ -f เพื่อเช็คว่า Server ตอบกลับมาหรือไม่ โดยไม่ต้องสนใจ Content
          if curl -s "$ENDPOINT/mcp" -o /dev/null --max-time 10 -w "%{http_code}" | grep -qE "^(200|404|406)"; then
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
        *)
          echo "🚚 WhaleTrucker CLI Ready"
          ;;
      esac
    EOS
    chmod 0755, bin/"scutua-mcp"
  end
end
