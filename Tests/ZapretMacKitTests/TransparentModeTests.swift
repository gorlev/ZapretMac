import Testing
@testable import ZapretMacKit

@Suite("Transparent mode (S-080)")
struct TransparentModeTests {
    let folders = HelperArguments.allowedFolders(home: "/Users/me")
    let data = "/Users/me/Library/Application Support/ZapretMac"

    func problem(_ arguments: [String]) -> String? {
        HelperArguments.problem(in: arguments, allowedFolders: folders)
    }

    @Test func pfRulesFollowZapretsMacSetup() {
        #expect(PFRules.anchorText(port: 1088) == """
        rdr pass on lo0 inet proto tcp from !127.0.0.0/8 to any port {80,443} -> 127.0.0.1 port 1088
        pass out route-to (lo0 127.0.0.1) inet proto tcp from any to any port {80,443} user { >root }
        rdr pass on lo0 inet6 proto tcp from !::1 to any port {80,443} -> fe80::1 port 1088
        pass out route-to (lo0 fe80::1) inet6 proto tcp from any to any port {80,443} user { >root }

        """)
        #expect(PFRules.anchorText(port: 2000, ports: [443]).contains("port {443} -> 127.0.0.1 port 2000"))
        #expect(HelperInfo.anchor == "com.apple/zapretmac")
        #expect(HelperInfo.machServiceName == "com.gorlev.zapretmac.helper")
    }

    @Test func acceptsEveryPreset() {
        for preset in Preset.all {
            #expect(problem(preset.options.arguments) == nil, "\(preset.id)")
        }
    }

    @Test func acceptsScanAndProfileFlags() {
        let arguments = [
            "--debug=1", "--filter-tcp=443", "--hostlist=\(data)/hostlist.txt",
            "--hostlist-exclude=\(data)/hostlist-exclude.txt", "--tlsrec=sniext+1", "--split-pos=1,midsld",
            "--new", "--filter-tcp=80", "--hostcase", "--disorder", "--disorder=http", "--oob", "--hostpad=1024",
            "--methodeol", "--domcase", "--mss=88", "--hostlist-domains=example.com",
            "--hostlist=/tmp/ZapretMac-self-2.store-files/hostlist.txt",
        ]
        #expect(problem(arguments) == nil)
    }

    @Test func refusesFlagsTheHelperOwns() {
        for flag in ["--user=nobody", "--uid=0:0", "--daemon", "--pidfile=/tmp/x.pid", "--port=80",
                     "--bind-addr=0.0.0.0", "--socks", "--enable-pf", "--connect-bind-addr=1.2.3.4",
                     "--hostlist-auto=\(data)/auto.txt", "--version", "--help", "--us=root"] {
            #expect(problem([flag]) != nil, "\(flag)")
        }
    }

    @Test func refusesDebugToAFile() {
        #expect(problem(["--debug=@/etc/sudoers"]) != nil)
        #expect(problem(["--debug=@\(data)/log.txt"]) != nil)
        #expect(problem(["--debug"]) == nil)
        #expect(problem(["--debug=syslog"]) == nil)
    }

    @Test func refusesPathsOutsideTheAppsFolders() {
        for path in ["/etc/hosts", "relative.txt", "\(data)/../../../.ssh/id_rsa", "\(data)/./x", "\(data)/",
                     "/Users/other/Library/Application Support/ZapretMac/hostlist.txt",
                     "/tmp/evil.txt", "/tmp/ZapretMac-x/hostlist.txt", "/tmp/ZapretMac-a-files/",
                     "/tmp/ZapretMac-a-files/../../etc/hosts", "@/etc/hosts", ""] {
            #expect(problem(["--hostlist=\(path)"]) != nil, "\(path)")
            #expect(problem(["--ipset-exclude=\(path)"]) != nil, "\(path)")
        }
    }

    @Test func refusesWordsAndMalformedFlags() {
        #expect(problem(["nobody"]) != nil)
        #expect(problem(["--split-pos", "1"]) != nil)
        #expect(problem(["-d"]) != nil)
        #expect(problem(["--split-pos="]) != nil)
        #expect(problem(["--hostcase=1"]) != nil)
        #expect(problem(["--comment=a\nb"]) != nil)
        #expect(problem([]) == nil)
    }

    @Test func clientRequirementNamesTheAppAndTeam() {
        #expect(ClientRequirement.string(teamID: "AB12CD34EF")
                == "identifier \"com.gorlev.zapretmac\" and anchor apple generic and certificate leaf[subject.OU] = \"AB12CD34EF\"")
        #expect(ClientRequirement.string(teamID: "") == nil)
        #expect(ClientRequirement.string(teamID: "AB\" or true") == nil)
        #expect(ClientRequirement.string(teamID: "ab12cd34ef") == nil)
    }
}
