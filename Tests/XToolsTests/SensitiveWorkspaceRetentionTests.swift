@testable import XTools
import XToolsCore
import Foundation
import Testing

struct SensitiveValueSessionRetentionTests {
    @MainActor
    @Test func jwtAndBasicAuthSessionsSurvivePageRecreationWithinOneRepository() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let jwt = repository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.mode = .generate
        jwt.session.generateSecret = "0123456789abcdef0123456789abcdef"
        jwt.session.generatePayload = #"{"sub":"retained"}"#
        jwt.session.refreshGeneration()

        let basicAuth = repository.model(for: BasicAuthToolWorkspaceModel.key)
        basicAuth.session.username = "retained-user"
        basicAuth.session.password = "retained-password"
        basicAuth.session.parseInput = "Authorization: Basic dXNlcjpwYXNz"
        basicAuth.session.parse()

        let restoredJWT = repository.model(for: JWTToolWorkspaceModel.key)
        let restoredBasicAuth = repository.model(for: BasicAuthToolWorkspaceModel.key)

        #expect(restoredJWT === jwt)
        #expect(restoredJWT.session.generateSecret == "0123456789abcdef0123456789abcdef")
        #expect(restoredJWT.session.generatePayload == #"{"sub":"retained"}"#)
        #expect(!restoredJWT.session.generatedToken.isEmpty)
        #expect(restoredBasicAuth === basicAuth)
        #expect(restoredBasicAuth.session.username == "retained-user")
        #expect(restoredBasicAuth.session.password == "retained-password")
        #expect(restoredBasicAuth.session.parsedCredentials?.username == "user")
    }

    @MainActor
    @Test func newRepositoryStartsSensitiveSessionsFromProductDefaults() {
        let defaults = Self.defaults()
        let firstRepository = ToolWorkspaceRepository(defaults: defaults)
        let jwt = firstRepository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.generateSecret = "must-not-persist"
        jwt.session.parseInput = "must-not-persist"
        jwt.session.parseSecret = "must-not-persist"

        let basicAuth = firstRepository.model(for: BasicAuthToolWorkspaceModel.key)
        basicAuth.session.username = "must-not-persist"
        basicAuth.session.password = "must-not-persist"
        basicAuth.session.parseInput = "must-not-persist"

        let relaunchedRepository = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedJWT = relaunchedRepository.model(for: JWTToolWorkspaceModel.key)
        let relaunchedBasicAuth = relaunchedRepository.model(for: BasicAuthToolWorkspaceModel.key)

        #expect(relaunchedJWT !== jwt)
        #expect(relaunchedJWT.session.mode == .parse)
        #expect(relaunchedJWT.session.generateAlgorithm == .hs256)
        #expect(relaunchedJWT.session.generateSecret.isEmpty)
        #expect(relaunchedJWT.session.parseInput.isEmpty)
        #expect(relaunchedJWT.session.parseSecret.isEmpty)
        #expect(relaunchedJWT.session.generatedToken.isEmpty)
        #expect(relaunchedJWT.session.verificationResult == nil)

        #expect(relaunchedBasicAuth !== basicAuth)
        #expect(relaunchedBasicAuth.session.mode == .generate)
        #expect(relaunchedBasicAuth.session.username.isEmpty)
        #expect(relaunchedBasicAuth.session.password.isEmpty)
        #expect(relaunchedBasicAuth.session.parseInput.isEmpty)
        #expect(relaunchedBasicAuth.session.parsedCredentials == nil)
    }

    @MainActor
    @Test func explicitClearRemovesAllRetainedSensitiveDrafts() {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let jwt = repository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.generateSecret = "jwt-secret"
        jwt.session.parseInput = "jwt-input"
        jwt.session.parseSecret = "parse-secret"
        jwt.session.clearAll()

        #expect(jwt.session.generateSecret.isEmpty)
        #expect(jwt.session.parseInput.isEmpty)
        #expect(jwt.session.parseSecret.isEmpty)
        #expect(jwt.session.generatedToken.isEmpty)
        #expect(jwt.session.verificationResult == nil)

        let basicAuth = repository.model(for: BasicAuthToolWorkspaceModel.key)
        basicAuth.session.username = "user"
        basicAuth.session.password = "password"
        basicAuth.session.parseInput = "Basic dXNlcjpwYXNz"
        basicAuth.session.parse()
        basicAuth.session.clearAll()

        #expect(basicAuth.session.username.isEmpty)
        #expect(basicAuth.session.password.isEmpty)
        #expect(basicAuth.session.parseInput.isEmpty)
        #expect(basicAuth.session.parsedCredentials == nil)
        #expect(basicAuth.session.parseError == nil)
    }

    @MainActor
    @Test func sensitiveDraftValuesNeverEnterUserDefaults() {
        let suiteName = "SensitiveDraftNoDiskTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let repository = ToolWorkspaceRepository(defaults: defaults)

        var forbiddenValues = [
            "jwt-secret-never-persist",
            "jwt-input-never-persist",
            "basic-password-never-persist",
            "plaintext-never-persist",
            "encryption-key-never-persist",
            "obfuscator-input-never-persist"
        ]

        let jwt = repository.model(for: JWTToolWorkspaceModel.key)
        jwt.session.generateSecret = forbiddenValues[0]
        jwt.session.parseInput = forbiddenValues[1]

        let basicAuth = repository.model(for: BasicAuthToolWorkspaceModel.key)
        basicAuth.session.password = forbiddenValues[2]

        let encryption = repository.model(for: TextEncryptionToolWorkspaceModel.key)
        encryption.input = forbiddenValues[3]
        encryption.password = forbiddenValues[4]

        let obfuscator = repository.model(for: StringObfuscatorToolWorkspaceModel.key)
        obfuscator.input = forbiddenValues[5]
        forbiddenValues.append(obfuscator.output)

        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(Set(domain.keys).isSubset(of: Set(SensitiveToolPreferenceKeys.allRawKeys)))
        for value in domain.values {
            let description = String(describing: value)
            for forbidden in forbiddenValues {
                #expect(!description.contains(forbidden))
            }
        }
    }

    @Test func revealStateStaysPageLocalAndOutsideRetainedModels() throws {
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(jwt, "@State private var showsGenerateSecret = false", "JWT generation secret must be hidden whenever page content is recreated")
        contains(jwt, "@State private var showsParseSecret = false", "JWT parse secret must be hidden whenever page content is recreated")
        contains(basicAuth, "@State private var showsPassword = false", "Basic Auth password must be hidden whenever page content is recreated")
        contains(basicAuth, "@State private var showsParsedPassword = false", "Parsed Basic Auth password must be hidden whenever page content is recreated")

        let jwtModel = sourceSlice(jwt, from: "final class JWTToolWorkspaceModel", to: "struct IndexJWTPage")
        let basicModel = sourceSlice(basicAuth, from: "final class BasicAuthToolWorkspaceModel", to: "struct IndexBasicAuthPage")
        doesNotContain(jwtModel, "showsGenerateSecret", "JWT reveal state must not enter retained workspace storage")
        doesNotContain(jwtModel, "showsParseSecret", "JWT reveal state must not enter retained workspace storage")
        doesNotContain(basicModel, "showsPassword", "Basic Auth reveal state must not enter retained workspace storage")
        doesNotContain(basicModel, "showsParsedPassword", "Parsed password reveal state must not enter retained workspace storage")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "SensitiveValueSessionRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct CryptoTransformWorkspaceRetentionTests {
    @MainActor
    @Test func hashWorkContinuesInRetainedModelAndOnlyEncodingRelaunches() async throws {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let hash = repository.model(for: HashTextToolWorkspaceModel.key)

        hash.encoding = "base64url"
        hash.input = "retained hash input"

        let restoredBeforeCompletion = repository.model(for: HashTextToolWorkspaceModel.key)
        #expect(restoredBeforeCompletion === hash)
        #expect(restoredBeforeCompletion.input == "retained hash input")

        for _ in 0..<100 where restoredBeforeCompletion.digests.count != 8 {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(restoredBeforeCompletion.digests.count == 8)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: HashTextToolWorkspaceModel.key)
        #expect(relaunched !== hash)
        #expect(relaunched.encoding == "base64url")
        #expect(relaunched.input.isEmpty)
        #expect(relaunched.digests.isEmpty)
    }

    @MainActor
    @Test func textEncryptionRetainsWorkInMemoryButReturnsToSafeRelaunchDefaults() throws {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let encryption = repository.model(for: TextEncryptionToolWorkspaceModel.key)

        encryption.password = "session-only-key"
        encryption.input = "session-only-plaintext"
        encryption.run()
        #expect(!encryption.output.isEmpty)

        let restored = repository.model(for: TextEncryptionToolWorkspaceModel.key)
        #expect(restored === encryption)
        #expect(restored.password == "session-only-key")
        #expect(restored.input == "session-only-plaintext")
        #expect(!restored.output.isEmpty)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: TextEncryptionToolWorkspaceModel.key)
        #expect(relaunched !== encryption)
        #expect(relaunched.mode == "enc")
        #expect(relaunched.algorithm == TextEncryptionService.Algorithm.aesGCM.rawValue)
        #expect(relaunched.password.isEmpty)
        #expect(relaunched.input.isEmpty)
        #expect(relaunched.output.isEmpty)
        #expect(relaunched.error == nil)
    }

    @MainActor
    @Test func textEncryptionClearRemovesRetainedSecretInputOutputAndDiagnostics() {
        let encryption = ToolWorkspaceRepository(defaults: Self.defaults())
            .model(for: TextEncryptionToolWorkspaceModel.key)
        encryption.password = "secret"
        encryption.input = "plaintext"
        encryption.error = "diagnostic"
        encryption.output = "ciphertext"

        encryption.clearSensitiveState()

        #expect(encryption.password.isEmpty)
        #expect(encryption.input.isEmpty)
        #expect(encryption.output.isEmpty)
        #expect(encryption.error == nil)
    }

    @MainActor
    @Test func stringObfuscatorKeepsWorkPerSessionAndOnlyValidatedRecipeAcrossRelaunch() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let obfuscator = repository.model(for: StringObfuscatorToolWorkspaceModel.key)

        obfuscator.keepFirst = 2
        obfuscator.keepLast = 1
        obfuscator.keepSpaces = false
        obfuscator.setReplacementCharacter("#")
        obfuscator.input = "sensitive draft"
        #expect(!obfuscator.output.isEmpty)

        let restored = repository.model(for: StringObfuscatorToolWorkspaceModel.key)
        #expect(restored === obfuscator)
        #expect(restored.input == "sensitive draft")
        #expect(!restored.output.isEmpty)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: StringObfuscatorToolWorkspaceModel.key)
        #expect(relaunched.keepFirst == 2)
        #expect(relaunched.keepLast == 1)
        #expect(relaunched.keepSpaces == false)
        #expect(relaunched.replacementChar == "#")
        #expect(relaunched.input.isEmpty)
        #expect(relaunched.output.isEmpty)
    }

    @MainActor
    @Test func invalidHashAndObfuscatorPreferencesFallBackToCurrentDefaults() {
        let defaults = Self.defaults()
        defaults.set("future-encoding", forKey: SensitiveToolPreferenceKeys.hashDigestEncoding.rawKey)
        defaults.set(-1, forKey: SensitiveToolPreferenceKeys.obfuscatorKeepFirst.rawKey)
        defaults.set(99, forKey: SensitiveToolPreferenceKeys.obfuscatorKeepLast.rawKey)
        defaults.set("##", forKey: SensitiveToolPreferenceKeys.obfuscatorReplacementCharacter.rawKey)

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let hash = repository.model(for: HashTextToolWorkspaceModel.key)
        let obfuscator = repository.model(for: StringObfuscatorToolWorkspaceModel.key)

        #expect(hash.encoding == "hex")
        #expect(obfuscator.keepFirst == 4)
        #expect(obfuscator.keepLast == 4)
        #expect(obfuscator.replacementChar == "*")
    }

    @MainActor
    @Test func sensitivePreferenceEnumerationContainsOnlyApprovedRecipeKeys() {
        let expected = Set([
            "tools.hashText.digestEncoding.v1",
            "tools.stringObfuscator.keepFirst.v1",
            "tools.stringObfuscator.keepLast.v1",
            "tools.stringObfuscator.keepSpaces.v1",
            "tools.stringObfuscator.replacementCharacter.v1",
            "tools.tokenGenerator.mode.v1",
            "tools.tokenGenerator.length.v1",
            "tools.tokenGenerator.quantity.v1",
            "tools.tokenGenerator.lowercaseEnabled.v1",
            "tools.tokenGenerator.uppercaseEnabled.v1",
            "tools.tokenGenerator.numbersEnabled.v1",
            "tools.tokenGenerator.symbolsEnabled.v1",
            "tools.uuidGenerator.quantity.v1",
            "tools.uuidGenerator.version.v1",
            "tools.passwordGenerator.length.v1",
            "tools.passwordGenerator.quantity.v1",
            "tools.passwordGenerator.lowercaseEnabled.v1",
            "tools.passwordGenerator.uppercaseEnabled.v1",
            "tools.passwordGenerator.numbersEnabled.v1",
            "tools.passwordGenerator.symbolsEnabled.v1",
            "tools.passwordGenerator.excludeAmbiguous.v1"
        ])

        #expect(Set(SensitiveToolPreferenceKeys.allRawKeys) == expected)
        for rawKey in SensitiveToolPreferenceKeys.allRawKeys {
            let normalized = rawKey.lowercased()
            #expect(!normalized.contains(".secret"))
            #expect(!normalized.contains(".input"))
            #expect(!normalized.contains(".content"))
            #expect(!normalized.contains(".result"))
            #expect(!normalized.contains(".output"))
            #expect(!normalized.contains(".tokens"))
            #expect(!normalized.contains(".passwords"))
            #expect(!normalized.contains(".verification"))
        }
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "CryptoTransformWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

struct GeneratorWorkspaceRetentionTests {
    @MainActor
    @Test func legacyTokenRecipeWithoutModeKeyRemainsCharacterSetMode() {
        let defaults = Self.defaults()
        defaults.set(12, forKey: SensitiveToolPreferenceKeys.tokenLength.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenLowercaseEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenUppercaseEnabled.rawKey)
        defaults.set(true, forKey: SensitiveToolPreferenceKeys.tokenNumbersEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenSymbolsEnabled.rawKey)

        let token = ToolWorkspaceRepository(defaults: defaults)
            .model(for: TokenGeneratorToolWorkspaceModel.key)

        #expect(token.mode == .characterSet)
        #expect(token.length == 12)
        #expect(!token.lower)
        #expect(!token.upper)
        #expect(token.numbers)
        #expect(!token.symbols)
        token.generate()
        #expect(token.tokens.count == 1)
        #expect(token.tokens[0].count == 12)
        #expect(token.tokens[0].allSatisfy { $0.isNumber })
    }

    @MainActor
    @Test func tokenPasswordAndUUIDResultsRemainStableWithinOneRepository() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let token = repository.model(for: TokenGeneratorToolWorkspaceModel.key)
        token.length = 24
        token.quantity = 2
        token.symbols = true
        token.generate()
        let tokenSnapshot = token.tokens

        let password = repository.model(for: PasswordGeneratorToolWorkspaceModel.key)
        password.length = 20
        password.quantity = 2
        password.symbols = true
        password.generate()
        let passwordSnapshot = password.passwords.map(\.value)

        let uuid = repository.model(for: UUIDGeneratorToolWorkspaceModel.key)
        uuid.quantity = 3
        uuid.generate()
        let uuidSnapshot = uuid.values

        #expect(repository.model(for: TokenGeneratorToolWorkspaceModel.key) === token)
        #expect(repository.model(for: TokenGeneratorToolWorkspaceModel.key).tokens == tokenSnapshot)
        #expect(repository.model(for: PasswordGeneratorToolWorkspaceModel.key) === password)
        #expect(repository.model(for: PasswordGeneratorToolWorkspaceModel.key).passwords.map(\.value) == passwordSnapshot)
        #expect(repository.model(for: UUIDGeneratorToolWorkspaceModel.key) === uuid)
        #expect(repository.model(for: UUIDGeneratorToolWorkspaceModel.key).values == uuidSnapshot)
    }

    @MainActor
    @Test func generatorRecipesRelaunchButGeneratedSecretsAndIdentifiersDoNot() {
        let defaults = Self.defaults()
        let firstRepository = ToolWorkspaceRepository(defaults: defaults)

        let token = firstRepository.model(for: TokenGeneratorToolWorkspaceModel.key)
        token.mode = .hex
        token.length = 48
        token.quantity = 3
        token.lower = true
        token.upper = false
        token.numbers = true
        token.symbols = true
        token.generate()
        #expect(!token.tokens.isEmpty)

        let password = firstRepository.model(for: PasswordGeneratorToolWorkspaceModel.key)
        password.length = 28
        password.quantity = 4
        password.lower = true
        password.upper = true
        password.numbers = false
        password.symbols = true
        password.excludeAmbiguous = false
        password.generate()
        #expect(!password.passwords.isEmpty)

        let uuid = firstRepository.model(for: UUIDGeneratorToolWorkspaceModel.key)
        uuid.version = .v7
        uuid.quantity = 7
        uuid.generate()
        #expect(!uuid.values.isEmpty)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedToken = relaunched.model(for: TokenGeneratorToolWorkspaceModel.key)
        let relaunchedPassword = relaunched.model(for: PasswordGeneratorToolWorkspaceModel.key)
        let relaunchedUUID = relaunched.model(for: UUIDGeneratorToolWorkspaceModel.key)

        #expect(relaunchedToken.length == 48)
        #expect(relaunchedToken.mode == .hex)
        #expect(relaunchedToken.quantity == 3)
        #expect(relaunchedToken.lower)
        #expect(!relaunchedToken.upper)
        #expect(relaunchedToken.numbers)
        #expect(relaunchedToken.symbols)
        #expect(relaunchedToken.tokens.isEmpty)
        #expect(relaunchedToken.error == nil)

        #expect(relaunchedPassword.length == 28)
        #expect(relaunchedPassword.quantity == 4)
        #expect(relaunchedPassword.lower)
        #expect(relaunchedPassword.upper)
        #expect(!relaunchedPassword.numbers)
        #expect(relaunchedPassword.symbols)
        #expect(!relaunchedPassword.excludeAmbiguous)
        #expect(relaunchedPassword.passwords.isEmpty)
        #expect(relaunchedPassword.error == nil)

        #expect(relaunchedUUID.quantity == 7)
        #expect(relaunchedUUID.version == .v7)
        #expect(relaunchedUUID.values.isEmpty)
    }

    @MainActor
    @Test func invalidGeneratorRecipesFallBackToSafeCurrentDefaults() {
        let defaults = Self.defaults()
        defaults.set(0, forKey: SensitiveToolPreferenceKeys.tokenLength.rawKey)
        defaults.set(99, forKey: SensitiveToolPreferenceKeys.tokenQuantity.rawKey)
        defaults.set("future-mode", forKey: SensitiveToolPreferenceKeys.tokenMode.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenLowercaseEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenUppercaseEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenNumbersEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.tokenSymbolsEnabled.rawKey)
        defaults.set(1, forKey: SensitiveToolPreferenceKeys.passwordLength.rawKey)
        defaults.set(99, forKey: SensitiveToolPreferenceKeys.passwordQuantity.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.passwordLowercaseEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.passwordUppercaseEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.passwordNumbersEnabled.rawKey)
        defaults.set(false, forKey: SensitiveToolPreferenceKeys.passwordSymbolsEnabled.rawKey)
        defaults.set(0, forKey: SensitiveToolPreferenceKeys.uuidQuantity.rawKey)
        defaults.set("future-version", forKey: SensitiveToolPreferenceKeys.uuidVersion.rawKey)

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let token = repository.model(for: TokenGeneratorToolWorkspaceModel.key)
        let password = repository.model(for: PasswordGeneratorToolWorkspaceModel.key)
        let uuid = repository.model(for: UUIDGeneratorToolWorkspaceModel.key)

        #expect(token.length == 32)
        #expect(token.quantity == 1)
        #expect(token.mode == .characterSet)
        #expect(token.lower)
        #expect(token.upper)
        #expect(token.numbers)
        #expect(!token.symbols)

        #expect(password.length == 16)
        #expect(password.quantity == 5)
        #expect(password.lower)
        #expect(password.upper)
        #expect(password.numbers)
        #expect(!password.symbols)
        #expect(password.excludeAmbiguous)

        #expect(uuid.quantity == 8)
        #expect(uuid.version == .v4)
    }

    @MainActor
    @Test func failedGeneratorAttemptIsRetainedAndDoesNotBecomeAnOnAppearRetryTrigger() throws {
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        let token = repository.model(for: TokenGeneratorToolWorkspaceModel.key)
        token.lower = false
        token.upper = false
        token.numbers = false
        token.symbols = false
        token.generate()
        #expect(token.hasAttemptedGeneration)
        #expect(token.tokens.isEmpty)
        #expect(token.error != nil)
        token.lower = true
        token.generate()
        #expect(!token.tokens.isEmpty)
        #expect(token.error == nil)

        let password = repository.model(for: PasswordGeneratorToolWorkspaceModel.key)
        password.lower = false
        password.upper = false
        password.numbers = false
        password.symbols = false
        password.generate()
        #expect(password.hasAttemptedGeneration)
        #expect(password.passwords.isEmpty)
        #expect(password.error != nil)
        password.lower = true
        password.generate()
        #expect(!password.passwords.isEmpty)
        #expect(password.error == nil)

        let tokenSource = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let passwordSource = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")
        contains(tokenSource, "if !workspace.hasAttemptedGeneration { generate() }", "Token navigation must not retry an already-retained failure")
        contains(passwordSource, "if !workspace.hasAttemptedGeneration { generate() }", "Password navigation must not retry an already-retained failure")
    }

    @MainActor
    @Test func generatedValuesNeverEnterUserDefaults() {
        let (defaults, suiteName) = Self.defaultsWithSuiteName()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let token = repository.model(for: TokenGeneratorToolWorkspaceModel.key)
        let password = repository.model(for: PasswordGeneratorToolWorkspaceModel.key)
        let uuid = repository.model(for: UUIDGeneratorToolWorkspaceModel.key)
        token.generate()
        password.generate()
        uuid.generate()

        let forbiddenValues = Set(token.tokens + password.passwords.map(\.value) + uuid.values)
        let storedValues = Array((defaults.persistentDomain(forName: suiteName) ?? [:]).values)
        for value in storedValues {
            if let string = value as? String {
                #expect(!forbiddenValues.contains(string))
            }
            if let strings = value as? [String] {
                #expect(forbiddenValues.isDisjoint(with: strings))
            }
        }
    }

    private static func defaults() -> UserDefaults {
        defaultsWithSuiteName().0
    }

    private static func defaultsWithSuiteName() -> (UserDefaults, String) {
        let suiteName = "GeneratorWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

struct WebUtilityWorkspaceRetentionTests {
    @MainActor
    @Test func httpAndUserAgentWorkSurviveNavigationButNotRelaunch() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let http = repository.model(for: HTTPStatusToolWorkspaceModel.key)
        http.query = "not found"
        http.category = "4xx 客户端错误"

        let userAgent = repository.model(for: UserAgentToolWorkspaceModel.key)
        userAgent.input = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
        userAgent.parse()
        #expect(!userAgent.browser.isEmpty)

        #expect(repository.model(for: HTTPStatusToolWorkspaceModel.key) === http)
        #expect(repository.model(for: HTTPStatusToolWorkspaceModel.key).query == "not found")
        #expect(repository.model(for: HTTPStatusToolWorkspaceModel.key).category == "4xx 客户端错误")
        #expect(repository.model(for: UserAgentToolWorkspaceModel.key) === userAgent)
        #expect(repository.model(for: UserAgentToolWorkspaceModel.key).input == userAgent.input)
        #expect(repository.model(for: UserAgentToolWorkspaceModel.key).browser == userAgent.browser)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedHTTP = relaunched.model(for: HTTPStatusToolWorkspaceModel.key)
        let relaunchedUserAgent = relaunched.model(for: UserAgentToolWorkspaceModel.key)
        #expect(relaunchedHTTP.query.isEmpty)
        #expect(relaunchedHTTP.category == "全部")
        #expect(relaunchedUserAgent.input.isEmpty)
        #expect(relaunchedUserAgent.browser.isEmpty)
        #expect(relaunchedUserAgent.error == nil)
    }

    @MainActor
    @Test func keyboardEventSnapshotSurvivesNavigationWhileListeningStaysViewLocal() throws {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let keycode = repository.model(for: KeycodeToolWorkspaceModel.key)
        keycode.snapshot = KeycodeMapper.snapshot(for: KeyboardEventInput(
            kind: .modifierFlagsChanged,
            keyCode: 0x36,
            characters: nil,
            charactersIgnoringModifiers: nil,
            modifiers: .init(command: true),
            isRepeat: false
        ))

        let restored = repository.model(for: KeycodeToolWorkspaceModel.key)
        #expect(restored === keycode)
        #expect(restored.snapshot?.keyCode == 0x36)
        #expect(restored.snapshot?.webCode == "MetaRight")

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: KeycodeToolWorkspaceModel.key)
        #expect(relaunched.snapshot == nil)

        let source = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        contains(source, "@State private var isListening = false", "Keyboard capture listening state must reset with the recreated view")
        let model = sourceSlice(source, from: "final class KeycodeToolWorkspaceModel", to: "struct IndexKeycodePage")
        doesNotContain(model, "isListening", "Keyboard capture focus state must not enter retained tool state")
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "WebUtilityWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
