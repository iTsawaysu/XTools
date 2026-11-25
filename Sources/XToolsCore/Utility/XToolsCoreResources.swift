import Foundation

enum XToolsCoreResources {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        let main = Bundle.main
        if main.object(forInfoDictionaryKey: "XToolsPackageInputDigest") is String {
            return main.url(forResource: name, withExtension: ext, subdirectory: "XToolsCore")
        }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
