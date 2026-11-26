@testable import Core
import Testing

private typealias Name = ContactNameEntries.Name
private typealias Entry = ContactNameEntries.Entry

@Test func contactWithFullPhoneticNameRegistersFullFamilyAndGivenNames() {
    let name = Name(familyName: "山田", givenName: "太郎", phoneticFamilyName: "やまだ", phoneticGivenName: "たろう")
    #expect(ContactNameEntries.entries(from: name) == [
        Entry(word: "山田太郎", reading: "やまだたろう"),
        Entry(word: "山田", reading: "やまだ"),
        Entry(word: "太郎", reading: "たろう")
    ])
}

@Test func contactWithoutPhoneticNameIsSkipped() {
    let name = Name(familyName: "山田", givenName: "太郎", phoneticFamilyName: "", phoneticGivenName: "")
    #expect(ContactNameEntries.entries(from: name).isEmpty)
}

@Test func onlyPartsWithPhoneticNameAreRegistered() {
    let familyOnly = Name(familyName: "山田", givenName: "太郎", phoneticFamilyName: "ヤマダ", phoneticGivenName: "")
    #expect(ContactNameEntries.entries(from: familyOnly) == [Entry(word: "山田", reading: "ヤマダ")])

    let givenOnly = Name(familyName: "", givenName: "花子", phoneticFamilyName: "", phoneticGivenName: "はなこ")
    #expect(ContactNameEntries.entries(from: givenOnly) == [Entry(word: "花子", reading: "はなこ")])
}

@Test func phoneticNameWithNonKanaCharactersIsSkipped() {
    let name = Name(familyName: "Smith", givenName: "John", phoneticFamilyName: "Smith", phoneticGivenName: "ジョン")
    #expect(ContactNameEntries.entries(from: name) == [Entry(word: "John", reading: "ジョン")])
}

@Test func whitespaceIsTrimmedAndRemovedFromReading() {
    let name = Name(familyName: " 山田 ", givenName: "", phoneticFamilyName: "やま だ", phoneticGivenName: "")
    #expect(ContactNameEntries.entries(from: name) == [Entry(word: "山田", reading: "やまだ")])
}

@Test func duplicateEntriesAcrossContactsAreRemoved() {
    let names = [
        Name(familyName: "山田", givenName: "太郎", phoneticFamilyName: "やまだ", phoneticGivenName: "たろう"),
        Name(familyName: "山田", givenName: "花子", phoneticFamilyName: "やまだ", phoneticGivenName: "はなこ")
    ]
    #expect(ContactNameEntries.entries(from: names) == [
        Entry(word: "山田太郎", reading: "やまだたろう"),
        Entry(word: "山田", reading: "やまだ"),
        Entry(word: "太郎", reading: "たろう"),
        Entry(word: "山田花子", reading: "やまだはなこ"),
        Entry(word: "花子", reading: "はなこ")
    ])
}

@Test func kanaReadingAcceptsLongVowelMark() {
    #expect(ContactNameEntries.isKanaReading("ジョーンズ"))
    #expect(ContactNameEntries.isKanaReading("ゆうこ"))
    #expect(!ContactNameEntries.isKanaReading("yamada"))
    #expect(!ContactNameEntries.isKanaReading("山だ"))
}
