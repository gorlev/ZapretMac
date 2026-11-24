# Translator brief: ZapretMac

You are writing the copy for **ZapretMac** in one language. Read:

1. `Localization/en.json`: the brief. **Not a source text.** Each entry has `en` (what the string must communicate; an object for plural keys), `where` (the Swift file and line), `line` (the code around it, which shows whether it is a button, a toggle, a tooltip (`.help`), a section title, a menu item, or a sentence), and sometimes `note`.
2. `Localization/notes.json` `_note`: extra context for some keys. It is also copied into `note` in en.json.

Write your version to `Localization/<code>.json`.

## What this is

ZapretMac is a free, open-source Mac app that turns on zapret's `tpws` engine with one switch so that sites an internet provider blocks with DPI filtering (Discord, YouTube, and others) open again. It runs a small local proxy on the Mac, offers ready-made "strategies" (ways of cutting up and disguising the first packets of a connection), lists of sites to unblock or never touch, a site check that compares with and without the app, a live log, and a menu bar switch. The readers are everyday Mac users in countries with internet censorship, from people who just want Discord to work to technical users who know zapret from Linux or Windows. They are a little anxious about breaking their internet; the copy should feel calm, plain, and confident.

## The job

The English is a brief, not a source text. For every string, ask what it is telling the reader, then write that the way a native speaker writing a Mac app for this audience would have written it if the English had never existed. If the natural sentence has a different shape, a different number of clauses, or a different subject, write the natural sentence.

Read every string aloud. If you would not say it to a colleague, it is wrong. "Does this read like a translation?" is the only test that matters.

- **Sound like macOS in your language.** Menu items, buttons, and settings use the words and grammar Apple uses in your language's macOS (imperative vs infinitive for buttons, sentence vs title case, "Settings…" ellipsis style, how "Turn On" / "Quit" / "Duplicate" / "Undo" read).
- **Never calque these English figures of speech** (say the plain thing your language says): "goes straight through", "Point your browser at it", "Turned back when it stops" (the system proxy setting is restored), "keeps running while it tests", "the filter cannot read it", "never sees it whole", "Everything at Once", "Never Touch", "In use", "Still blocked", "works on most providers", "Hold for the tpws command" (press and hold the button).
- **Use the words this community actually uses.** zapret users talk about "DPI", "proxy", "strategy", "split", "disorder", "SNI". Where your language's tech users keep an English term, keep it; where an ordinary native word exists, use it. Decide per term.
- **Form of address, one voice throughout:**
  - tr: address the reader the way macOS Turkish does: polite imperative (`-in`, e.g. "Seçin", "Ekleyin"), never `sen`.
  - de: `du`, as current macOS German does.
  - es: `tú`, neutral international Spanish (no regionalisms from one country).
  - it: `tu`.
  - fr: `vous`.
  - pt-BR: `você`, Brazilian Portuguese.
  - ru: `вы` (lowercase), as macOS Russian does.
- **Mind the space.** These sit in tight spots, so keep them as short as the English or shorter: sidebar page names (Overview, Strategies, Sites, Log); segmented controls (All sites / My list, Sites to Unblock / Never Touch, All / Sites / Errors); small row buttons ("Use", "In use"); stat tile labels ("Running for", "Connections", "Sites seen"); strategy names on cards; the menu bar menu title "Bypass"; status words "Off", "Bypass On". Tooltips and help sentences can be as long as they need.
- Built-in strategy names ("TLS Record + Split", "Split at Domain", "Split + Disorder", "Out-of-Band Byte", "HTTP Header Tricks", "Everything at Once") are product labels: write natural short names; keep technical words (TLS, HTTP) as your users say them.

## The contract

- Exactly the same keys as en.json. Plural keys (where `en` is an object) become an object of plural categories; every other value is a string.
- Placeholders: `%@` is text (a strategy name, a site like `discord.com`, a port number like `1088`, or an error message), `%lld` is a whole number. Keep the same number of each kind. You may move them anywhere and rebuild the sentence around them; to reorder two of them use positional forms `%1$@`, `%2$lld`.
- Plural categories: tr, de, es, it, fr, pt-BR need `one` and `other`. ru needs `one`, `few`, `many`, `other` (`other` is for fractions; make it the same as `many`). In plural keys, a `one` form may hard-code the number or drop it (Russian `one` also fires for 21, 31, so keep `%lld` in Russian `one` when the number is shown). Keep `%@` in every form.
- Verbatim, never translated: ZapretMac, zapret, tpws, bol-van, GitHub, MIT, Safari, Chrome, SOCKS5, TLS, HTTP, DPI, 127.0.0.1, ./build.sh, `Host:`, `host:`, the tpws flag names and markers in parentheses or lists (oob, disorder, method, host, endhost, sld, midsld, endsld, sniext, +N, -N), and domains (youtube.com, discord.com, mybank.com).
- Keyboard shortcuts in tooltips: keep them in parentheses at the end, naming the keys the way macOS menus in your language do.
- Typography: your language's own quotes and punctuation (French thin space before `: ; ? !` is optional; if you use it, use it everywhere), the single-character ellipsis `…` where the English has it.

## Before you finish

Run `python3 tools/l10n.py check <code>` and fix everything it reports until it prints PASS.

Report back: the 5–10 strings you departed from the English on most, old and new, one line each, with the reason. Then any string you were unsure about and why. Nothing else.
