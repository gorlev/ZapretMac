import Foundation
import Testing
@testable import ZapretMacKit

@Test func hostSpellAndPadRoundTrip() {
    let o = StrategyOptions(commandLine: "--split-pos=method+2 --hostcase --hostspell=hoSt --hostpad=2048")
    #expect(o.hostSpell == "hoSt")
    #expect(o.hostPad == "2048")
    #expect(o.extra.isEmpty)
    #expect(o.arguments == ["--split-pos=method+2", "--hostcase", "--hostspell=hoSt", "--hostpad=2048"])
    #expect(StrategyOptions(arguments: o.arguments) == o)
}

@Test func hostSpellAndPadComeBeforeExtraFlags() {
    var o = StrategyOptions()
    o.hostPad = " 1024 "
    o.hostSpell = "HOST"
    o.extra = ["--tamper-cutoff=n2"]
    #expect(o.arguments == ["--hostspell=HOST", "--hostpad=1024", "--tamper-cutoff=n2"])
}

@Test func summaryCountsHostSpellAndPad() {
    #expect(StrategyOptions(commandLine: "--hostspell=hoSt --hostpad=2048").summary == "2 HTTP tricks")
    #expect(StrategyOptions(commandLine: "--hostcase --hostpad=2048").summary == "2 HTTP tricks")
}

@Test func warnsAboutOOBWithDisorder() {
    #expect(StrategyOptions(commandLine: "--split-pos=1,midsld --oob --disorder").macOSWarnings == [.oobWithDisorder])
    #expect(StrategyOptions(commandLine: "--split-pos=1 --oob").macOSWarnings.isEmpty)
    #expect(StrategyOptions(commandLine: "--split-pos=1 --disorder").macOSWarnings.isEmpty)
}

@Test func warnsAboutLinuxOnlyFlags() {
    #expect(StrategyOptions(commandLine: "--mss=88").macOSWarnings == [.linuxOnly(flag: "--mss")])
    #expect(StrategyOptions(commandLine: "--fix-seg").macOSWarnings == [.linuxOnly(flag: "--fix-seg")])
    #expect(StrategyOptions(commandLine: "--oob --disorder --fix-seg=100 --mss=88 --mss=100").macOSWarnings
        == [.oobWithDisorder, .linuxOnly(flag: "--fix-seg"), .linuxOnly(flag: "--mss")])
    #expect(StrategyOptions(commandLine: "--tamper-cutoff=n2 --mssx").macOSWarnings.isEmpty)
}

@Test func builtInPresetsHaveNoMacWarnings() {
    for preset in Preset.all {
        #expect(preset.options.macOSWarnings.isEmpty, "\(preset.id)")
    }
}
