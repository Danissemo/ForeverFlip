# Ukrainian localization and readable text 5.2.3

Fresh read-only review identified two important issues: overview height measured
before content refresh and untranslated raw/prefixed errors. Regression tests
reproduce both, fixes move layout after refresh and translate raw/prefix messages.
A single-value regression prevents Lua string.gsub's replacement count leaking
into variadic UI calls. All catalog glyphs are checked with fontTools against
bundled unmodified OFL Noto Sans. Missing arrow glyphs become ASCII.
The canonical dictionary is Locale.lua; financial formulas and receipts unchanged.
Language selection writes only db.ui.language through normal in-game SavedVariables.
Installer does not edit WTF. Native item names/descriptions remain client language.
Live WoW rendering still requires /reload and visual confirmation.
