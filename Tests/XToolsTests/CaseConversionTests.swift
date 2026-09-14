import XToolsCore
import Testing

struct CaseConversionTests {
    // MARK: - Word splitting

    @Test func splitsOnCamelHumps() {
        #expect(CaseConversion.words("helloWorld") == ["hello", "world"])
        #expect(CaseConversion.words("parseHTTPRequest") == ["parse", "http", "request"])
        #expect(CaseConversion.words("HTTPRequest") == ["http", "request"])
    }

    @Test func splitsOnSeparatorsAndWhitespace() {
        #expect(CaseConversion.words("hello_world") == ["hello", "world"])
        #expect(CaseConversion.words("hello-world") == ["hello", "world"])
        #expect(CaseConversion.words("hello.world/path") == ["hello", "world", "path"])
        #expect(CaseConversion.words("hello   world") == ["hello", "world"])
        // Runs of separators collapse to a single split.
        #expect(CaseConversion.words("a__b--c") == ["a", "b", "c"])
    }

    @Test func keepsDigitsWithAdjacentWordUnlessCamelBoundaryRequiresSplit() {
        #expect(CaseConversion.words("version2HTTPServer") == ["version2", "http", "server"])
        #expect(CaseConversion.words("ipv6_address") == ["ipv6", "address"])
    }

    @Test func returnsEmptyForNoWordCharacters() {
        #expect(CaseConversion.words("").isEmpty)
        #expect(CaseConversion.words("   ").isEmpty)
        #expect(CaseConversion.words("___").isEmpty)
    }

    // MARK: - Case styles

    @Test func rendersEveryStyleInTableOrder() {
        let styles = CaseConversion.styles("hello world foo")
        #expect(styles.map(\.label) == [
            "camelCase", "PascalCase", "snake_case", "kebab-case",
            "CONSTANT", "Title Case", "UPPER", "lower"
        ])
        #expect(styles.map(\.value) == [
            "helloWorldFoo",
            "HelloWorldFoo",
            "hello_world_foo",
            "hello-world-foo",
            "HELLO_WORLD_FOO",
            "Hello World Foo",
            "HELLO WORLD FOO",
            "hello world foo"
        ])
    }

    @Test func camelKeepsFirstWordLowercase() {
        let styles = CaseConversion.styles("hello")
        let byLabel = Dictionary(uniqueKeysWithValues: styles.map { ($0.label, $0.value) })
        #expect(byLabel["camelCase"] == "hello")   // first word stays lowercase
        #expect(byLabel["PascalCase"] == "Hello")
        #expect(byLabel["CONSTANT"] == "HELLO")
    }

    @Test func returnsEmptyStylesForNoWords() {
        #expect(CaseConversion.styles("").isEmpty)
        #expect(CaseConversion.styles("___").isEmpty)
    }

    @Test func differentInputStylesConvergeToSameOutput() {
        // camelCase, snake_case and kebab-case inputs all tokenize identically.
        let fromCamel = CaseConversion.styles("myVariableName")
        let fromSnake = CaseConversion.styles("my_variable_name")
        let fromKebab = CaseConversion.styles("my-variable-name")
        #expect(fromCamel.map(\.value) == fromSnake.map(\.value))
        #expect(fromSnake.map(\.value) == fromKebab.map(\.value))
        #expect(fromCamel.first(where: { $0.label == "PascalCase" })?.value == "MyVariableName")
    }

    @Test func acronymInputRendersExpectedStyles() {
        let styles = CaseConversion.styles("parseHTTPRequest")
        let byLabel = Dictionary(uniqueKeysWithValues: styles.map { ($0.label, $0.value) })

        #expect(byLabel["camelCase"] == "parseHttpRequest")
        #expect(byLabel["PascalCase"] == "ParseHttpRequest")
        #expect(byLabel["snake_case"] == "parse_http_request")
        #expect(byLabel["CONSTANT"] == "PARSE_HTTP_REQUEST")
    }
}
