# NOTE: Comments in this Formula are intentionally written in English,
# following the de facto Homebrew ecosystem convention (homebrew-core and
# nearly all personal taps use English-only). This is an explicit, scoped
# exception to the project-wide "Japanese comments in source code" policy
# stated in CLAUDE.md / AGENTS.md.
#
# Rationale: a Formula is an interface to the Homebrew ecosystem (anyone
# can run `brew edit swift-selena`; the file is a candidate for future
# homebrew-core submission; external contributors familiar with Homebrew
# expect English). Keeping it English minimizes friction. Comments inside
# Swift source code under Sources/ continue to follow the project policy
# and are written in Japanese.

class SwiftSelena < Formula
  desc "MCP Server for Swift code analysis"
  homepage "https://github.com/BlueEventHorizon/Swift-Selena"
  url "https://github.com/BlueEventHorizon/Swift-Selena.git",
      tag:      "0.6.11",
      revision: "4c636a53319f58fd192857fb079417c42ebeb68d"
  license "MIT"

  # macOS 13.0+ requirement matches Package.swift's .macOS(.v13).
  # `depends_on xcode` is intentionally omitted: the build is a plain SwiftPM
  # CLI build and Command Line Tools providing Swift 5.9+ should suffice.
  # If a CLT-only build is shown to fail, re-add `depends_on xcode: ["15.0", :build]`.
  depends_on macos: :ventura

  def install
    # `--disable-sandbox` lets SwiftPM fetch the remote dependencies declared
    # in Package.swift / pinned in Package.resolved during the install step.
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "-Xswiftc", "-Osize",
           "--product", "Swift-Selena"

    # The SwiftPM product is named "Swift-Selena" (see Package.swift).
    # Install it under a conventional lowercase command name.
    bin.install ".build/release/Swift-Selena" => "swift-selena"
  end

  def caveats
    <<~EOS
      Swift-Selena is installed as `swift-selena` and is on your PATH.

      To register with Claude Code:
        claude mcp add -s user swift-selena -- swift-selena

      To register with Claude Desktop, add the following to
      ~/Library/Application Support/Claude/claude_desktop_config.json
      (HOMEBREW_PREFIX is interpolated here, so copy-paste is safe):

        {
          "mcpServers": {
            "swift-selena": {
              "command": "#{HOMEBREW_PREFIX}/bin/swift-selena",
              "env": { "MCP_CLIENT_ID": "claude-desktop" }
            }
          }
        }

      Then restart the Claude app.

      Full documentation: #{homepage}
    EOS
  end

  test do
    require "open3"
    require "json"

    # The server speaks MCP JSON-RPC 2.0 over stdio. We send a single
    # `initialize` request, then read stdout until the response with id==1
    # arrives. Sending EOF immediately exits the server before it responds,
    # so we keep stdin open until the response is received or we time out.
    # stdout carries JSON-RPC only; the server's own logs go to a file
    # and stderr, which we intentionally discard via popen3's third channel.
    request = {
      jsonrpc: "2.0",
      id:      1,
      method:  "initialize",
      params:  {
        protocolVersion: "2024-11-05",
        capabilities:    {},
        clientInfo:      { name: "brew-test", version: "0" },
      },
    }.to_json

    response = nil
    Open3.popen3("#{bin}/swift-selena") do |stdin, stdout, _stderr, wait_thr|
      stdin.write("#{request}\n")
      stdin.flush

      deadline = Time.now + 10
      while Time.now < deadline
        next unless stdout.wait_readable(0.5)

        line = stdout.gets
        break if line.nil?

        parsed = begin
          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end
        if parsed && parsed["id"] == 1
          response = parsed
          break
        end
      end
    ensure
      begin
        stdin.close
      rescue IOError
        # already closed
      end

      if wait_thr.alive?
        begin
          Process.kill("TERM", wait_thr.pid)
        rescue Errno::ESRCH
          # already exited
        end
        unless wait_thr.join(2)
          begin
            Process.kill("KILL", wait_thr.pid)
          rescue Errno::ESRCH
            # already exited
          end
          wait_thr.join
        end
      end
    end

    refute_nil response, "MCP initialize response not received"
    assert_equal "Swift-Selena", response.dig("result", "serverInfo", "name")
  end
end
