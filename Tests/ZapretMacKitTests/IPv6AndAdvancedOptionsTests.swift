import Testing
@testable import ZapretMacKit

@Suite("Transparent mode for IPv6 (S-105)")
struct TransparentIPv6Tests {
    @Test func pfRulesHaveIPv4AndIPv6Lines() {
        let text = PFRules.anchorText(port: 1088)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines == [
            "rdr pass on lo0 inet proto tcp from !127.0.0.0/8 to any port {80,443} -> 127.0.0.1 port 1088",
            "pass out route-to (lo0 127.0.0.1) inet proto tcp from any to any port {80,443} user { >root }",
            "rdr pass on lo0 inet6 proto tcp from !::1 to any port {80,443} -> fe80::1 port 1088",
            "pass out route-to (lo0 fe80::1) inet6 proto tcp from any to any port {80,443} user { >root }",
        ])
        #expect(text.hasSuffix("\n"))
        #expect(PFRules.anchorText(port: 2000, ports: [443]).contains("inet6 proto tcp from !::1 to any port {443} -> fe80::1 port 2000"))
    }

    @Test func fixedArgumentsBindIPv4AndLinkLocalIPv6() {
        let fixed = HelperInfo.fixedTPWSArguments(port: 1088)
        #expect(fixed == ["--user=root", "--port=1088", "--bind-addr=127.0.0.1", "--bind-iface6=lo0", "--bind-linklocal=force"])
        // --bind-linklocal applies to the bind started just before it, so it must follow --bind-iface6.
        #expect(fixed.firstIndex(of: "--bind-iface6=lo0")! + 1 == fixed.firstIndex(of: "--bind-linklocal=force")!)
    }

    @Test func clientsStillCannotSendBindFlags() {
        let folders = HelperArguments.allowedFolders(home: "/Users/me")
        for flag in ["--bind-iface6=en0", "--bind-linklocal=force", "--bind-iface4=en0", "--bind-addr=::",
                     "--bind-wait-ifup=5", "--bind-wait-ip=5", "--bind-wait-ip-linklocal=5", "--bind-wait-only"] {
            #expect(HelperArguments.problem(in: [flag], allowedFolders: folders) != nil, "\(flag)")
        }
    }
}

@Suite("Remaining tpws options in the editor (S-107)")
struct AdvancedOptionsTests {
    func roundTrips(_ line: String) -> StrategyOptions {
        let o = StrategyOptions(commandLine: line)
        #expect(o.commandLine == line, "\(line)")
        #expect(StrategyOptions(arguments: o.arguments) == o, "\(line)")
        return o
    }

    @Test func oobDataRoundTrips() {
        #expect(roundTrips("--oob --oob-data=0x01").oobData == "0x01")
        #expect(roundTrips("--oob --oob-data=X").oobData == "X")
        #expect(StrategyOptions(commandLine: "--oob-data=0x01").extra.isEmpty)
    }

    @Test func disorderScopeRoundTrips() {
        let all = roundTrips("--disorder")
        #expect(all.disorder && all.disorderScope == .all)
        let http = roundTrips("--disorder=http")
        #expect(http.disorder && http.disorderScope == .http && http.extra.isEmpty)
        let tls = roundTrips("--disorder=tls")
        #expect(tls.disorder && tls.disorderScope == .tls)
        var o = StrategyOptions()
        o.disorder = true
        o.disorderScope = .tls
        #expect(o.arguments == ["--disorder=tls"])
        o.disorder = false
        #expect(o.arguments.isEmpty)
    }

    @Test func oobScopeRoundTrips() {
        #expect(roundTrips("--oob").oobScope == .all)
        let http = roundTrips("--oob=http")
        #expect(http.oob && http.oobScope == .http)
        #expect(roundTrips("--oob=tls").oobScope == .tls)
    }

    @Test func unknownOrRepeatedScopesStayInExtra() {
        // tpws takes --disorder=http and --disorder=tls together; the form shows the first.
        let both = StrategyOptions(commandLine: "--disorder=http --disorder=tls")
        #expect(both.disorderScope == .http && both.extra == ["--disorder=tls"])
        #expect(both.arguments == ["--disorder=http", "--disorder=tls"])
        #expect(StrategyOptions(commandLine: "--oob=quic").extra == ["--oob=quic"])
        #expect(StrategyOptions(commandLine: "--disorder=all").extra == ["--disorder=all"])
    }

    @Test func protocolFilterRoundTrips() {
        let o = roundTrips("--filter-l7=http,tls,unknown")
        #expect(L7Protocol.allCases.allSatisfy(o.filters))
        #expect(roundTrips("--filter-l7=tls,http").protocolFilter == "tls,http")
        var p = StrategyOptions()
        p.setFilter(.tls, true)
        p.setFilter(.http, true)
        #expect(p.arguments == ["--filter-l7=http,tls"])
        p.setFilter(.http, false)
        #expect(p.filters(.tls) && !p.filters(.http) && !p.filters(.unknown))
        p.setFilter(.tls, false)
        #expect(p.arguments.isEmpty)
    }

    @Test func tamperLimitsRoundTrip() {
        let o = roundTrips("--tamper-start=n2 --tamper-cutoff=n3")
        #expect(o.tamperStart == "n2" && o.tamperCutoff == "n3" && o.extra.isEmpty)
        #expect(roundTrips("--tamper-start=100").tamperStart == "100")
        // A second copy stays as written.
        #expect(StrategyOptions(commandLine: "--tamper-cutoff=n2 --tamper-cutoff=n4").extra == ["--tamper-cutoff=n4"])
    }

    @Test func everythingTogetherRoundTrips() {
        let line = "--split-pos=1,midsld --disorder=tls --oob=http --hostcase --oob-data=0x02"
            + " --filter-l7=http,tls --tamper-start=n1 --tamper-cutoff=n3"
        let o = roundTrips(line)
        #expect(o.extra.isEmpty)
    }

    @Test func existingStrategiesAreUnchanged() {
        for preset in Preset.all {
            let o = preset.options
            #expect(StrategyOptions(arguments: o.arguments) == o, "\(preset.id)")
            #expect(o.disorderScope == .all && o.oobScope == .all && o.oobData.isEmpty
                    && o.protocolFilter.isEmpty && o.tamperStart.isEmpty && o.tamperCutoff.isEmpty, "\(preset.id)")
        }
        for line in ["--split-pos=1,midsld --disorder", "--split-pos=1 --oob", "--tlsrec=sniext+1 --split-pos=midsld",
                     "--filter-tcp=80 --hostcase --new --filter-tcp=443 --disorder=tls --tamper-cutoff=n2"] {
            #expect(StrategyOptions(commandLine: line).commandLine == line, "\(line)")
        }
    }

    @Test func oobWithDisorderWarnsInAnyScope() {
        #expect(StrategyOptions(commandLine: "--disorder=tls --oob=tls").macOSWarnings == [.oobWithDisorder])
        #expect(StrategyOptions(commandLine: "--disorder --oob=http").macOSWarnings == [.oobWithDisorder])
        #expect(StrategyOptions(commandLine: "--disorder=http").macOSWarnings.isEmpty)
    }

    @Test func helperValidatorAcceptsTheNewOptions() {
        let folders = HelperArguments.allowedFolders(home: "/Users/me")
        let arguments = ["--oob-data=0x01", "--oob-data=X", "--disorder", "--disorder=http", "--disorder=tls",
                         "--oob", "--oob=http", "--oob=tls", "--filter-l7=http,tls,unknown",
                         "--tamper-start=n2", "--tamper-start=100", "--tamper-cutoff=n3"]
        for argument in arguments {
            #expect(HelperArguments.problem(with: argument, allowedFolders: folders) == nil, "\(argument)")
        }
        var o = StrategyOptions(commandLine: "--split-pos=1 --disorder=tls --oob=http --oob-data=0x02")
        o.protocolFilter = "http,tls"
        o.tamperStart = "n1"
        o.tamperCutoff = "n3"
        let command = TPWSCommand(port: 1088, strategy: o.arguments, scope: .allSites, debug: false, mode: .transparent)
        #expect(HelperArguments.problem(in: command.arguments, allowedFolders: folders) == nil)
        // Empty values and forbidden flags are still refused.
        for bad in ["--oob-data", "--oob-data=", "--filter-l7", "--tamper-start=", "--tamper-cutoff",
                    "--user=nobody", "--bind-addr=0.0.0.0", "--port=80"] {
            #expect(HelperArguments.problem(with: bad, allowedFolders: folders) != nil, "\(bad)")
        }
    }
}
