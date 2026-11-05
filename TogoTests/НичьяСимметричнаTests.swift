import Testing
import Foundation
@testable import Togo

/// Полная ничья — один ответ на обоих телефонах.
@Suite("Обмен · ничья симметрична")
struct НичьяСимметричнаTests {

    /// Прежде при равном времени и равном счёте побеждала МЕСТНАЯ —
    /// у каждого телефона своя, и дневник расходился молча.
    @Test("Ничья по времени и по заполненности решается одинаково с обеих сторон")
    func симметрия() {
        let id = UUID()
        let когда = Date()
        let а = ClinicPayload(id: id, name: "Vet Riviera", detail: nil, isLab: false,
                              phone: "+33 4 93 00 00 00", createdAt: когда, changedAt: когда)
        let б = ClinicPayload(id: id, name: "Vet Riviera", detail: nil, isLab: false,
                              phone: "+33 4 93 11 11 11", createdAt: когда, changedAt: когда)

        let уА = SharedDiaryMerge.resolve(local: а, remote: б)
        let уБ = SharedDiaryMerge.resolve(local: б, remote: а)

        #expect(уА == уБ, """
            два телефона решили одну ничью по-разному: у первого \
            \(уА.phone ?? "—"), у второго \(уБ.phone ?? "—"). Каждый \
            считает спор решённым, и дневник расходится до следующей правки.
            """)
    }

    /// Контроль: правило ничьей не перебивает «заполнено больше».
    @Test("При ничьей по времени заполненная по-прежнему побеждает")
    func заполненнаяПобеждает() {
        let id = UUID()
        let когда = Date()
        let полная = ClinicPayload(id: id, name: "Vet Riviera", detail: "Ницца", isLab: false,
                                   phone: "+33 4 93 00 00 00", createdAt: когда, changedAt: когда)
        let пустая = ClinicPayload(id: id, name: "Vet Riviera", detail: nil, isLab: false,
                                   phone: nil, createdAt: когда, changedAt: когда)
        #expect(SharedDiaryMerge.resolve(local: пустая, remote: полная) == полная)
        #expect(SharedDiaryMerge.resolve(local: полная, remote: пустая) == полная)
    }
}
