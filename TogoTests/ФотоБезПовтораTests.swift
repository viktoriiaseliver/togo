import Testing
import Foundation
import CloudKit
@testable import Togo

/// Фото записи не уезжает второй раз, если не менялось.
@Suite("Обмен · фото без повторной выгрузки")
struct ФотоБезПовтораTests {

    private let zone = CKRecordZone.ID(zoneName: SharedDiary.zoneName, ownerName: "_owner")

    private func событие(_ id: UUID, фото: Data?) -> EventPayload {
        EventPayload(id: id, dogID: nil, kind: "meal", date: Date(), authorName: "Вика",
                     note: nil, photo: фото, outcome: nil, durationSeconds: nil, stoolForm: nil,
                     stoolFlags: [], grams: 60, milliliters: nil, fromPortion: false,
                     incidentKind: nil, incidentDetail: nil, walkEventID: nil,
                     careTaskID: nil, medicationID: nil, deletedAt: nil,
                     deletedBy: nil, changedAt: Date())
    }

    /// Запись «как с сервера»: ассет указывает на файл с этими байтами.
    private func записьСФото(_ id: UUID, _ байты: Data) throws -> (CKRecord, CKAsset) {
        let запись = CKRecord(recordType: SharedDiary.RecordType.event.rawValue,
                              recordID: SharedDiaryRecords.recordID(id, in: zone))
        let файл = URL.temporaryDirectory.appending(path: "сервер-\(UUID().uuidString).bin")
        try байты.write(to: файл)
        let ассет = CKAsset(fileURL: файл)
        запись["photo"] = ассет
        return (запись, ассет)
    }

    @Test("То же фото — ассет на записи прежний, выгрузки нет")
    func тоЖеФото() throws {
        let id = UUID()
        let байты = Data(repeating: 7, count: 4096)
        let (запись, прежний) = try записьСФото(id, байты)

        SharedDiaryRecords.apply(событие(id, фото: байты), to: запись)

        #expect((запись["photo"] as? CKAsset) === прежний, """
            на записи новый ассет при том же фото — CloudKit выгрузит \
            снимок целиком ещё раз на правке заметки или граммов
            """)
    }

    @Test("Другое фото — новый ассет с новыми байтами")
    func другоеФото() throws {
        let id = UUID()
        let (запись, прежний) = try записьСФото(id, Data(repeating: 7, count: 4096))
        let новые = Data(repeating: 9, count: 4096)

        SharedDiaryRecords.apply(событие(id, фото: новые), to: запись)

        let ассет = try #require(запись["photo"] as? CKAsset)
        #expect(ассет !== прежний, "фото сменили, а на записи старый ассет")
        let url = try #require(ассет.fileURL)
        #expect(try Data(contentsOf: url) == новые)
    }

    @Test("Фото убрали — ассет снят, а не оставлен висеть")
    func фотоУбрали() throws {
        let id = UUID()
        let (запись, _) = try записьСФото(id, Data(repeating: 7, count: 16))

        SharedDiaryRecords.apply(событие(id, фото: nil), to: запись)

        #expect(запись["photo"] == nil)
    }

    @Test("Нет фото и не было — ответ «то же»")
    func пустоеПустое() {
        let запись = CKRecord(recordType: SharedDiary.RecordType.event.rawValue,
                              recordID: SharedDiaryRecords.recordID(UUID(), in: zone))
        #expect(SharedDiaryRecords.фотоУжеНаЗаписи(nil, запись))
        #expect(!SharedDiaryRecords.фотоУжеНаЗаписи(Data([1]), запись))
    }
}
