// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Span Brain
import Foundation
import Testing
import RFLocalization

struct CatalogLookupTests {
    private let fixtures: Bundle? = Bundle.module.url(forResource: "Fixtures", withExtension: nil).flatMap(Bundle.init(url:))

    @Test func translatedKeyUsesTheLocale() throws {
        let bundle = try #require(fixtures)
        #expect(CatalogLookup.text("fixture.greeting", bundle: bundle, locale: Locale(identifier: "zh-CN")) == "你好")
        #expect(CatalogLookup.text("fixture.greeting", bundle: bundle, locale: Locale(identifier: "en")) == "Hello")
    }

    @Test func missingTranslationFallsBackToEnglishNotTheKey() throws {
        let bundle = try #require(fixtures)
        #expect(CatalogLookup.text("fixture.englishOnly", bundle: bundle, locale: Locale(identifier: "zh-CN")) == "Only in English")
    }

    @Test func unsupportedLocaleUsesEnglish() throws {
        let bundle = try #require(fixtures)
        #expect(CatalogLookup.text("fixture.greeting", bundle: bundle, locale: Locale(identifier: "ar")) == "Hello")
        #expect(CatalogLookup.text("fixture.englishOnly", bundle: bundle, locale: Locale(identifier: "de-DE")) == "Only in English")
    }

    @Test func pluralMissingFromTheLocaleFallsBackToEnglishRules() throws {
        let bundle = try #require(fixtures)
        let resolved = CatalogLookup.resolve("fixture.files %lld", in: bundle, locale: Locale(identifier: "zh-CN"))
        #expect(resolved.locale.identifier == "en")
        #expect(String(localized: "fixture.files \(Int64(1))", bundle: resolved.bundle, locale: resolved.locale) == "1 file")
        #expect(String(localized: "fixture.files \(Int64(3))", bundle: resolved.bundle, locale: resolved.locale) == "3 files")
        #expect(CatalogLookup.format("fixture.files %lld", [Int64(2)], bundle: bundle, locale: Locale(identifier: "zh-CN")) == "2 files")
    }

    @Test func presentTranslationKeepsTheCallerLocale() throws {
        let bundle = try #require(fixtures)
        #expect(CatalogLookup.resolve("fixture.greeting", in: bundle, locale: Locale(identifier: "zh-CN")).locale.identifier == "zh-CN")
        #expect(CatalogLookup.resolve("fixture.greeting", in: bundle, locale: Locale(identifier: "en-GB")).locale.identifier == "en-GB")
        #expect(CatalogLookup.resolve("fixture.greeting", in: bundle, locale: Locale(identifier: "ar")).locale.identifier == "en")
    }

    @Test func expandedPseudoLocaleWrapsEnglish() throws {
        let bundle = try #require(fixtures)
        #expect(CatalogLookup.text("fixture.englishOnly", bundle: bundle, locale: Locale(identifier: "en-XA")) == "［Only in English · Only in English］")
        #expect(CatalogLookup.format("fixture.files %lld", [Int64(1)], bundle: bundle, locale: Locale(identifier: "en-XA")) == "［1 file · 1 file］")
    }
}
