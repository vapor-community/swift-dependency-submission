#!/usr/bin/env -S swift -enable-upcoming-feature ExistentialAny -enable-upcoming-feature BareSlashRegexLiterals

import Foundation

struct PackageDependency: Codable {
    let identity: String, name: String, url: String, version: String, path: String
    let dependencies: [PackageDependency]
}

struct SwiftPUrl: Codable, RawRepresentable, Hashable {
    let scheme: String, type: String, source: String, name: String, version: String
    
    var rawValue: String { "\(self.scheme):\(self.type)/\(self.source)/\(self.name)@\(self.version)" }
    
    init?(rawValue raw: String) {
        guard let match = raw.wholeMatch(of: #/pkg:swift/(?<sp>[^/]+)/(?<nm>[^@]+)@(?<ver>.+)/#) else { return nil }
        self.init(source: .init(match.sp), name: .init(match.nm), version: .init(match.ver))
    }    
    init(source: String, name: String, version: String) {
        (self.scheme, self.type) = ("pkg", "swift")
        (self.source, self.name, self.version) = (source, name, version)
    }
    init(with url: URL, version: String) {
        (self.scheme, self.type) = ("pkg", "swift")
        self.source = "\(url.host ?? "localhost")\(url.deletingLastPathComponent().path)"
        self.name = (url.pathExtension == "git" ? url.deletingPathExtension() : url).lastPathComponent
        self.version = version
    }
}

struct GithubDependencyGraph: Codable {
    struct Job: Codable { let correlator: String, id: String }
    struct Detector: Codable { let name: String, version: String, url: String }
    struct Manifest: Codable {
        struct File: Codable { let source_location: String }
        struct Package: Codable {
            let package_url: SwiftPUrl, scope: String, relationship: String, dependencies: [String]
            init(package_url: SwiftPUrl, dependencies: [String], relationship: String) {
                self.package_url = package_url
                self.scope = "runtime"
                self.dependencies = dependencies
                self.relationship = relationship
            }
        }
        let name: String, file: File, resolved: [String: Package]
    }
    let version: Int, sha: String, ref: String, job: Job, detector: Detector,
        scanned: Date, manifests: [String: Manifest]
}

func fail(_ message: @autoclosure () -> String) -> Never {
    try? FileHandle.standardError.write(contentsOf: Array("\(message())\n".utf8))
    exit(1)
}

func env(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name] else {
        fail("Incomplete environment: \(name)")
    }
    return value
}

func main() {
    let decoder = JSONDecoder(), encoder = JSONEncoder()
    decoder.dateDecodingStrategy = .iso8601
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]

    let branch = env("BRANCH"),
        commit = env("COMMIT"),
        correlator = env("CORRELATOR"),
        runId = env("GITHUB_RUN_ID"),
        detectorVer = env("GITHUB_ACTION_REF"),
        serverUrl = env("GITHUB_SERVER_URL")
    
    let topLevelDependencies = try! decoder.decode(
        PackageDependency.self,
        from: FileHandle.standardInput.readToEnd() ?? .init()
    ).dependencies
    
    var resolved = [SwiftPUrl: GithubDependencyGraph.Manifest.Package]()
    
    func handleDeps(_ dependencies: [PackageDependency]) {
        for dep in dependencies {
            guard let url = URL(string: dep.url) else {
                fail("Invalid URL for package \(dep.identity)")
            }
            let purl = SwiftPUrl(with: url, version: dep.version)
            guard !resolved.keys.contains(purl) else { continue }
            handleDeps(dep.dependencies)
            guard !resolved.keys.contains(purl) else { continue }
            resolved[purl] = .init(
                package_url: purl,
                dependencies: dep.dependencies.map {
                    SwiftPUrl(with: URL(string: $0.url)!, version: $0.version).rawValue
                }.sorted(),
                relationship: topLevelDependencies.map(\.identity).contains(dep.identity) ? "direct" : "indirect"
            )
        }
    }
    handleDeps(topLevelDependencies)

    let graph = GithubDependencyGraph(
        version: 0, sha: commit, ref: branch,
        job: .init(correlator: correlator, id: runId),
        detector: .init(
            name: "vapor-community/swift-dependency-submission",
            version: detectorVer.isEmpty ? "v0" : detectorVer,
            url: "\(serverUrl)/vapor-community/swift-dependency-submission"
        ),
        scanned: Date(),
        manifests: ["Package.resolved": .init(
            name: "Package.resolved",
            file: .init(source_location: "Package.resolved"),
            resolved: .init(uniqueKeysWithValues: resolved.map { ($0.rawValue, $1) })
        )]
    )
    
    print(String(decoding: try! encoder.encode(graph), as: UTF8.self))
}

main()
