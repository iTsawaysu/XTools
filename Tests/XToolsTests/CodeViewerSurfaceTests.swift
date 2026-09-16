import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

struct CodeViewerSurfaceTests {
    // MARK: - Syntax Highlighting Conversion Tests

    @Test func jsonHighlightingConvertsToNSAttributedStringWithColors() {
        let line = #"  "name": "XTools", "count": 42, "active": true"#
        let attributed = JSONSyntaxHighlighter.highlight(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        // Verify that attributes exist and foregroundColor is assigned
        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil {
                colorFound = true
            }
        }
        #expect(colorFound, "NSAttributedString converted from JSON highlight must retain foreground colors")
    }

    @Test func sqlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = "SELECT id, name FROM users WHERE active = true"
        let attributed = StructuredSyntaxHighlighter.sql(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil {
                colorFound = true
            }
        }
        #expect(colorFound, "NSAttributedString converted from SQL highlight must retain foreground colors")
    }

    @Test func sqlHighlightingHandlesRepeatedKeywordsOnSameLine() {
        let line = "SELECT id, (SELECT count(*) FROM orders) as total FROM users"
        let attributed = StructuredSyntaxHighlighter.sql(line: line)
        let nsAttr = NSAttributedString(attributed)

        var firstColor: Any?
        var secondColor: Any?

        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if range.location <= 0 && range.upperBound >= 6 { firstColor = value }
            if range.location <= 12 && range.upperBound >= 18 { secondColor = value }
        }

        #expect(firstColor != nil, "First SELECT must be highlighted")
        #expect(secondColor != nil, "Second SELECT on same line must also be highlighted")
    }

    @Test func yamlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = "database_host: 'localhost'"
        let attributed = StructuredSyntaxHighlighter.yaml(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil { colorFound = true }
        }
        #expect(colorFound, "YAML highlight must convert with colors")
    }

    @Test func xmlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = #"<user id="123" role="admin">Alice</user>"#
        let attributed = StructuredSyntaxHighlighter.xml(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil { colorFound = true }
        }
        #expect(colorFound, "XML highlight must convert with colors")
    }

    // MARK: - Real-World Payload Formatting & View Model Tests

    @Test func realWorldComplexJSONFormatsAndColors() throws {
        let complexJSON = """
        {
          "store": {
            "book": [
              {
                "category": "reference",
                "author": "Nigel Rees",
                "title": "Sayings of the Century",
                "price": 8.95
              },
              {
                "category": "fiction",
                "author": "Evelyn Waugh",
                "title": "Sword of Honour",
                "price": 12.99
              }
            ],
            "bicycle": {
              "color": "red",
              "price": 19.95,
              "available": true,
              "discount": null
            }
          }
        }
        """

        let formatted = try JSONFormatting.format(complexJSON, sortKeys: true, indentWidth: 2)
        #expect(!formatted.isEmpty)

        // Test each line through highlighter
        for line in formatted.components(separatedBy: "\n") {
            let highlighted = JSONSyntaxHighlighter.highlight(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldComplexSQLFormatsAndColors() throws {
        let complexSQL = """
        with recursive subordinates as (
            select employee_id, manager_id, full_name
            from employees
            where employee_id = 1
            union all
            select e.employee_id, e.manager_id, e.full_name
            from employees e
            inner join subordinates s on s.employee_id = e.manager_id
        )
        select employee_id, full_name
        from subordinates
        order by employee_id desc
        """

        let formatted = try SQLFormatting.format(complexSQL, options: .init(keywordCase: .upper, indentWidth: 2, commaStyle: .trailing))
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("WITH"))
        #expect(formatted.contains("SELECT"))

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.sql(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldYAMLFormatsAndColors() throws {
        let complexYAML = """
        version: "3.8"
        services:
          web:
            image: nginx:alpine
            ports:
              - "80:80"
            environment:
              NODE_ENV: production
              DEBUG: false
            restart: always
        """

        let formatted = try YAMLPrettifier.formatValidated(complexYAML)
        #expect(!formatted.isEmpty)

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.yaml(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldXMLFormatsAndColors() throws {
        let complexXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <configuration>
            <server port="8080" host="0.0.0.0">
                <ssl enabled="true" certificate="/etc/ssl/cert.pem"/>
            </server>
            <database>
                <driver>postgresql</driver>
                <url>jdbc:postgresql://localhost:5432/mydb</url>
                <credentials>
                    <username>admin</username>
                    <password>secret</password>
                </credentials>
            </database>
        </configuration>
        """

        let formatted = try XMLFormatting.format(complexXML, indentWidth: 2)
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("<?xml"))
        #expect(formatted.contains("<server port=\"8080\""))

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.xml(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @MainActor
    @Test func jsonFormatterInitializesWithCleanEmptyState() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.\(UUID().uuidString)")!
        let store = ToolPreferenceStore(defaults: defaults)
        let model = JSONFormatterToolWorkspaceModel(preferences: store)
        #expect(model.input.isEmpty, "JSON formatter input must start empty without pre-seeded sample text")
        #expect(model.output.isEmpty, "JSON formatter output must start empty")
        #expect(model.error == nil)
        #expect(model.warning == nil)
    }

    @MainActor
    @Test func jsonFormatterPageMountsWithCleanEmptyStateInHostingView() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.Mount.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexJSONFormatterPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        let key = JSONFormatterToolWorkspaceModel.key
        let model = repository.model(for: key)
        #expect(model.input.isEmpty, "JSON input must be completely empty on initial mount")
        #expect(model.output.isEmpty, "JSON output must be completely empty on initial mount")
    }
}
