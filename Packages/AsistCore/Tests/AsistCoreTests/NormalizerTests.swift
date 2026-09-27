import Foundation
import XCTest
@testable import AsistCore

/// 02 §3 (normalisation) and §4 (tokenisation).
final class NormalizerTests: XCTestCase {

    func testApostropheVariantsBecomeAscii() {
        XCTAssertEqual(Normalizer.normalize("Ahmet’i ara"), "Ahmet'i ara")
        XCTAssertEqual(Normalizer.normalize("Ahmet´i ara"), "Ahmet'i ara")
        XCTAssertEqual(Normalizer.normalize("Ahmet‘i ara"), "Ahmet'i ara")
        XCTAssertEqual(Normalizer.normalize("saat 10’da"), "saat 10'da")
    }

    func testWhitespaceIsCollapsedAndTrimmed() {
        XCTAssertEqual(Normalizer.normalize("  15:30'da  müşteri   araması "), "15:30'da müşteri araması")
        XCTAssertEqual(Normalizer.normalize("yarın\tsaat\n3'te"), "yarın saat 3'te")
        XCTAssertEqual(Normalizer.normalize("yarın\u{00A0}sabah"), "yarın sabah")
    }

    func testDetachedSuffixIsJoinedToTheNumber() {
        XCTAssertEqual(Normalizer.normalize("yarın saat 3 te ahmeti ara"), "yarın saat 3'te ahmeti ara")
        XCTAssertEqual(Normalizer.normalize("carsamba 14:30 da toplantı"), "carsamba 14:30'da toplantı")
        XCTAssertEqual(Normalizer.normalize("Perşembe saat 15:45 te kalibrasyon"), "Perşembe saat 15:45'te kalibrasyon")
        XCTAssertEqual(Normalizer.normalize("3 'te gel"), "3'te gel")
        // "de"/"da" only after a number ≤ 24 or a clock (02 §3 step 4).
        XCTAssertEqual(Normalizer.normalize("400 de kaldı"), "400 de kaldı")
        XCTAssertEqual(Normalizer.normalize("yarın 2 de gelsin"), "yarın 2'de gelsin")
    }

    func testTrailingPunctuationIsStripped() {
        XCTAssertEqual(Normalizer.normalize("Yarın saat 15.00'te bütçe toplantısı."), "Yarın saat 15.00'te bütçe toplantısı")
        XCTAssertEqual(Normalizer.normalize("Bugün neler var?"), "Bugün neler var")
        XCTAssertEqual(Normalizer.normalize("Arka Cep FAT testi!…"), "Arka Cep FAT testi")
        XCTAssertEqual(Normalizer.normalize(""), "")
        XCTAssertEqual(Normalizer.normalize("   "), "")
    }

    func testNFCComposition() {
        // "I" + U+0307 composes to "İ".
        XCTAssertEqual(Normalizer.normalize("I\u{0307}zmir"), "İzmir")
    }

    func testTokenSeparatorsAndTrailingPunctuation() {
        let tokens = Tokenizer.tokenize("Yarın, saat 15.30'da, Arka Cep FAT testi").tokens
        XCTAssertEqual(tokens.map { $0.original }, ["Yarın", "saat", "15.30'da", "Arka", "Cep", "FAT", "testi"])
        XCTAssertEqual(tokens[0].trailingPunct, ",")
        XCTAssertEqual(tokens[2].trailingPunct, ",")
        XCTAssertNil(tokens[1].trailingPunct)
        let note = Tokenizer.tokenize("Not: yarın").tokens
        XCTAssertEqual(note.first?.original, "Not")
        XCTAssertEqual(note.first?.trailingPunct, ":")
        let hyphen = Tokenizer.tokenize("e-postaları kontrol et").tokens
        XCTAssertEqual(hyphen.first?.original, "e-postaları")
    }

    func testApostropheAndDigitSplit() {
        let tokens = Tokenizer.tokenize("PLC'yi 3te 15:30da Hat 3'te").tokens
        XCTAssertEqual(tokens[0].root, "plc")
        XCTAssertEqual(tokens[0].suffix, "yi")
        XCTAssertTrue(tokens[0].hadApostrophe)
        XCTAssertTrue(tokens[0].isAllCaps)
        XCTAssertEqual(tokens[1].root, "3")
        XCTAssertEqual(tokens[1].suffix, "te")
        XCTAssertFalse(tokens[1].hadApostrophe)
        XCTAssertTrue(tokens[1].isSplit)
        XCTAssertEqual(tokens[2].number, .clock(15, 30))
        XCTAssertEqual(tokens[2].suffix, "da")
        XCTAssertEqual(tokens[4].number, .integer(3))
        XCTAssertEqual(tokens[4].suffix, "te")
    }

    func testNumericShapes() {
        XCTAssertEqual(Token.parseNumeric("15:30"), .clock(15, 30))
        XCTAssertEqual(Token.parseNumeric("15.30"), .dotted(15, 30))
        XCTAssertEqual(Token.parseNumeric("12.11.2026"), .dottedDate(12, 11, 2026))
        XCTAssertEqual(Token.parseNumeric("12.11.26"), .dottedDate(12, 11, 2026))
        XCTAssertEqual(Token.parseNumeric("15/10"), .slashDate(15, 10, nil))
        XCTAssertEqual(Token.parseNumeric("10/11/2026"), .slashDate(10, 11, 2026))
        XCTAssertEqual(Token.parseNumeric("42"), .integer(42))
        XCTAssertEqual(Token.parseNumeric("1,5"), .half(1))
        XCTAssertEqual(Token.parseNumeric("1.5"), .half(1))
        XCTAssertNil(Token.parseNumeric("abc"))
        XCTAssertNil(Token.parseNumeric("1:2:3"))
    }

    func testCapitalisationFlags() {
        let tokens = Tokenizer.tokenize("Ahmet ABB İK hat").tokens
        XCTAssertTrue(tokens[0].isCapitalized)
        XCTAssertFalse(tokens[0].isAllCaps)
        XCTAssertTrue(tokens[1].isAllCaps)
        XCTAssertTrue(tokens[2].isAllCaps)
        XCTAssertFalse(tokens[3].isCapitalized)
    }

    func testFoldedFormsMatchDiacriticFreeTyping() {
        let a = Tokenizer.tokenize("çarşamba").tokens[0]
        let b = Tokenizer.tokenize("carsamba").tokens[0]
        XCTAssertEqual(a.plain, b.plain)
        let c = Tokenizer.tokenize("SALI").tokens[0]
        XCTAssertEqual(c.plain, "sali")
    }

    func testTokenRangesPointIntoTheNormalisedText() {
        let text = "not al saat 3'te gelen fiyat"
        let result = Tokenizer.tokenize(text)
        for token in result.tokens {
            XCTAssertEqual(String(result.chars[token.start..<token.end]), token.original)
        }
    }
}
