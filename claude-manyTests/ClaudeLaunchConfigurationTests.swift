import XCTest
@testable import claude_many

final class ClaudeLaunchConfigurationTests: XCTestCase {
    func testProfilesKeepSeparateCodeStateAndReplaceInheritedPaths() {
        let work = ClaudeLaunchConfiguration(dataDirectory: URL(fileURLWithPath: "/Profiles/Work Account"))
        let personal = ClaudeLaunchConfiguration(dataDirectory: URL(fileURLWithPath: "/Profiles/Personal"))
        let inherited = [
            "PATH": "/usr/bin:/bin",
            "CLAUDE_USER_DATA_DIR": "/legacy-profile",
            "CLAUDE_CONFIG_DIR": "/shared-code-config",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/shared-keychain-namespace"
        ]

        let environment = work.environment(inheriting: inherited)
        XCTAssertEqual(environment["PATH"], inherited["PATH"])
        XCTAssertNil(environment["CLAUDE_USER_DATA_DIR"])
        XCTAssertEqual(environment["CLAUDE_CONFIG_DIR"], "/Profiles/Work Account/.claude")
        XCTAssertEqual(environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"], environment["CLAUDE_CONFIG_DIR"])
        XCTAssertNotEqual(work.codeConfigurationDirectory, personal.codeConfigurationDirectory)
        XCTAssertNotEqual(environment["CLAUDE_CONFIG_DIR"],
                          personal.environment(inheriting: inherited)["CLAUDE_CONFIG_DIR"])
    }

    func testDataDirectoryPreservesSpaces() {
        let path = "/Profiles/Work Account/Ötzi"
        XCTAssertEqual(ClaudeLaunchConfiguration.dataDirectory(in: ["--user-data-dir=\(path)"])?.path, path)
    }

    func testLastDirectorySwitchWins() {
        XCTAssertEqual(ClaudeLaunchConfiguration.dataDirectory(in: [
            "--user-data-dir=/first", "--user-data-dir=/last"
        ])?.path, "/last")
        XCTAssertNil(ClaudeLaunchConfiguration.dataDirectory(in: [
            "--user-data-dir=/first", "--user-data-dir="
        ]))
        XCTAssertNil(ClaudeLaunchConfiguration.dataDirectory(in: [
            "--user-data-dir=/first", "--user-data-dir", "/not-a-switch-value"
        ]))
    }

    func testIgnoresArgumentsAfterTerminator() {
        XCTAssertNil(ClaudeLaunchConfiguration.dataDirectory(in: ["--", "--user-data-dir=/ignored"]))
        XCTAssertEqual(ClaudeLaunchConfiguration.dataDirectory(in: [
            "--user-data-dir=/profile", "--", "--user-data-dir=/ignored"
        ])?.path, "/profile")
    }

    func testMissingRelativeAndUnrelatedPathsAreNotProfiles() {
        for arguments in [
            [], ["--user-data-dir"], ["--user-data-dir="], ["--user-data-dir=relative"],
            ["--user-data-dir", "/not-a-switch-value"],
            ["--user-data-dir", "--other-switch"], ["--user-data-directory=/other"],
            ["CLAUDE_USER_DATA_DIR=/legacy"], ["--title=--user-data-dir=/other"]
        ] {
            XCTAssertNil(ClaudeLaunchConfiguration.dataDirectory(in: arguments), "\(arguments)")
        }
    }
}
