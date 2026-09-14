import XToolsCore
import Testing

struct TestMarkdownRegressionSuiteTests {
    @Test func xmlMixedContentSamplePreservesVisibleInlineContent() throws {
        let output = try XMLFormatting.format(
            #"<article><p>Hello <strong>world</strong>, this is <em>mixed</em> content.</p><br/><img src="/logo.png" alt="Logo"/></article>"#
        )

        #expect(output.contains("Hello <strong>world</strong>"))
        #expect(output.contains("this is <em>mixed</em>"))
        #expect(output.contains("content.</p>"))
        #expect(output.contains("<br></br>") || output.contains("<br/>"))
        #expect(output.contains("src=\"/logo.png\""))
        #expect(output.contains("alt=\"Logo\""))
    }

    @Test func yamlLongSampleKeepsAnchorsAliasesAndBlockScalars() throws {
        let output = try YAMLPrettifier.formatValidated(
            """
            defaults: &defaults
              retries: 3
              timeout_ms: 120000
              headers:
                Accept: application/json
                X-Trace: "toolkit-test"

            services:
              api:
                <<: *defaults
                image: example/api:2.4.0
                ports:
                  - "8080:8080"
                environment:
                  NODE_ENV: production
                  FEATURE_FLAGS: "json,sql,xml,yaml"
                command:
                  - node
                  - server.js

            release_notes: |
              第一行保持原样。
              第二行也保持换行。
              JSON 示例：{"id":1,"ok":true}

            folded_text: >
              这段文字会被折叠成一行，
              但段落之间的空行需要保留。

            numbers:
              quoted_number: "00123"
            """
        )

        #expect(output.contains("defaults: &defaults"))
        #expect(output.contains("<<: *defaults"))
        #expect(output.contains("release_notes: |"))
        #expect(output.contains("第一行保持原样。"))
        #expect(output.contains("JSON 示例：{\"id\":1,\"ok\":true}"))
        #expect(output.contains("folded_text: >"))
        #expect(output.contains("quoted_number: \"00123\""))
    }

    @Test func textDiffLongChineseSampleDetectsChangedLine() {
        let left = "开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具尤其不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为一行很长就破坏整体布局。"
        let right = "开发者工具应优先给出清晰、可恢复、可理解的错误信息。格式化工具不能在输入非法时伪造成功结果，因为这会让用户把错误数据复制到生产配置中。对于较长文本，差异视图需要保持滚动同步、行号稳定，并且不要因为某一行特别长就破坏整体布局。"

        let diff = LineDiffer.diff(left: left, right: right)

        #expect(diff.contains("共 1 行不同"))
        #expect(diff.contains("格式化工具尤其不能"))
        #expect(diff.contains("格式化工具不能"))
        #expect(diff.contains("某一行特别长"))
    }

    @Test func regexUnicodeUFlagBoundaryIsExplicit() {
        #expect(throws: RegexMatcher.MatcherError.unsupportedFlag("u")) {
            _ = try RegexMatcher.analyze(
                pattern: #"[\p{Script=Han}]+"#,
                in: "Hello 世界, JSON 格式化, emoji 🙂, kana カタカナ",
                flags: "gu"
            )
        }
    }

    @Test func dockerNetworkHostsDNSAndCommandSampleArePreserved() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run -d --name postgres-client --network dev-net --network-alias db-client --add-host host.docker.internal:host-gateway --dns 1.1.1.1 postgres:16 psql -h db -U app"
        )

        #expect(result.yaml.contains("container_name: postgres-client"))
        #expect(result.yaml.contains(#"image: "postgres:16""#))
        #expect(result.yaml.contains("dev-net"))
        #expect(result.yaml.contains("db-client"))
        #expect(result.yaml.contains("extra_hosts:"))
        #expect(result.yaml.contains("host.docker.internal:host-gateway"))
        #expect(result.yaml.contains("dns:"))
        #expect(result.yaml.contains("1.1.1.1"))
        #expect(result.yaml.contains("command:"))
        #expect(result.yaml.contains("- psql"))
        #expect(result.yaml.contains("- -h"))
        #expect(result.yaml.contains("- db"))
        #expect(result.notTranslatable.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func dockerComplexEnvironmentSampleKeepsEmptyEqualsAndJSONValues() throws {
        let result = try DockerRunToDockerComposeService.convert(
            #"docker run --name env-test -e EMPTY= -e TOKEN="abc=123==xyz" -e JSON='{"enabled":true,"count":3}' alpine:3.20 env"#
        )

        #expect(result.yaml.contains("container_name: env-test"))
        #expect(result.yaml.contains(#"image: "alpine:3.20""#))
        #expect(result.yaml.contains("EMPTY="))
        #expect(result.yaml.contains("TOKEN=abc=123==xyz"))
        #expect(result.yaml.contains(#"JSON={\"enabled\":true,\"count\":3}"#) || result.yaml.contains(#"JSON={"enabled":true,"count":3}"#))
        #expect(result.yaml.contains("command:"))
        #expect(result.yaml.contains("- env"))
    }

    @Test func htmlLongSampleKeepsReadableMarkdownStructures() {
        let markdown = HTMLToMarkdownConverter.convert(
            """
            <article>
              <h1>开发者工具箱发布说明</h1>
              <p>这个版本改进了 <strong>JSON 格式化</strong>、<em>文本对比</em> 和 <code>Docker Run → Compose</code>。</p>
              <h2>功能列表</h2>
              <ul>
                <li>支持 Unicode 文本。</li>
                <li>保留代码块和链接。</li>
                <li>尽量转换表格。</li>
              </ul>
              <h2>对比表</h2>
              <table>
                <thead>
                  <tr><th>工具</th><th>输入</th><th>输出</th></tr>
                </thead>
                <tbody>
                  <tr><td>JSON</td><td>压缩 JSON</td><td>格式化 JSON</td></tr>
                  <tr><td>HTML</td><td>HTML 文档</td><td>Markdown</td></tr>
                </tbody>
              </table>
              <blockquote>
                <p>错误输入不能伪装成成功输出。</p>
              </blockquote>
              <pre><code>const ok = true;
            console.log(JSON.stringify({ ok }, null, 2));</code></pre>
              <p><img src="/assets/toolkit.png" alt="工具箱截图" title="Toolkit"></p>
            </article>
            """
        )

        #expect(markdown.contains("# 开发者工具箱发布说明"))
        #expect(markdown.contains("**JSON 格式化**"))
        #expect(markdown.contains("*文本对比*"))
        #expect(markdown.contains("`Docker Run → Compose`"))
        #expect(markdown.contains("## 功能列表"))
        #expect(markdown.contains("+ 支持 Unicode 文本。"))
        #expect(markdown.contains("| 工具 | 输入 | 输出 |"))
        #expect(markdown.contains(">"))
        #expect(markdown.contains("错误输入不能伪装成成功输出。"))
        #expect(markdown.contains("```\nconst ok = true;"))
        #expect(markdown.contains("![工具箱截图](/assets/toolkit.png \"Toolkit\")"))
    }

    @Test func quickRegressionMixedPayloadSamplesStayInTheirToolBoundaries() throws {
        let yaml = try YAMLPrettifier.formatValidated(
            #"""
            payloads:
              json: '{"id":1,"ok":true}'
              sql: "select id,name from users where active=1"
              html: "<p>Hello <strong>world</strong></p>"
              regex: "\\b\\w+@example\\.com\\b"
            """#
        )
        #expect(yaml.contains(#"json: '{"id":1,"ok":true}'"#))
        #expect(yaml.contains(#"sql: "select id,name from users where active=1""#))
        #expect(yaml.contains(#"html: "<p>Hello <strong>world</strong></p>""#))
        #expect(yaml.contains(#"regex: "\\b\\w+@example\\.com\\b""#))

        let textDiff = LineDiffer.diff(
            left: "SQL:\nselect * from users where id = 1;",
            right: "SQL:\nselect * from users where id = 2;"
        )
        #expect(textDiff.contains("共 1 行不同"))
        #expect(textDiff.contains("id = 1"))
        #expect(textDiff.contains("id = 2"))
    }
}
