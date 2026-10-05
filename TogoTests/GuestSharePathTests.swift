import Foundation
import CloudKit
import Testing
@testable import Togo

/// Гость и владелец адресуют облако по-разному — и до 05.10 `FamilyShare`
/// адресовал его одинаково, молча.
///
/// **Как это выглядело у человека.** Виктория сказала про экран «Семья»
/// одну строку: «провели много времени пытаясь настроить». Журнал
/// подтверждал числом — 44 захода против 31 у главного экрана, — а причину
/// числа не называют. Вот она, по ролям:
///
/// ```
/// гость жмёт «Пригласить»   заводил В СВОЕЙ базе ВТОРОЙ дневник, пустой,
///                           и делился им. На экране — как будто удалось
/// гость смотрит участников  спрашивал свою личную базу → пусто.
///                           Экран при этом обещает «Все видят одно и то же»
/// гость жмёт «Перестать»    удалял несуществующее, получал успех
///                           и оставался в чужом дневнике
/// ```
///
/// Общего у всех трёх одно: `SharedZoneRouting` **существовал, был верен
/// и вызывался из двух мест в `FamilySync`**, а `FamilyShare` все четыре
/// раза адресовал базу и зону руками. Сторож на вызов это пропустил бы:
/// вызовы есть, просто не отовсюду.
@MainActor
@Suite("Путь гостя в общем дневнике")
struct GuestSharePathTests {

    /// Чужое имя владельца, как оно приходит из `CKShare.Metadata`.
    private static let чужой = "_ownerOfSomeoneElsesDiary"

    private func какГость<T>(_ тело: () async throws -> T) async rethrows -> T {
        let было = SharedZoneOwner.name
        SharedZoneOwner.name = Self.чужой
        defer { SharedZoneOwner.name = было }
        return try await тело()
    }

    private func какВладелец<T>(_ тело: () async throws -> T) async rethrows -> T {
        let было = SharedZoneOwner.name
        SharedZoneOwner.reset()
        defer { SharedZoneOwner.name = было }
        return try await тело()
    }

    // MARK: - Сначала проверка, что набору было что проверять

    @Test("Подстановка владельца действительно переключает роль")
    func оснасткаРаботает() async {
        await какГость {
            #expect(SharedZoneOwner.isGuest, "Без этого остальные тесты зелены, ничего не проверив.")
        }
        await какВладелец {
            #expect(SharedZoneOwner.isGuest == false)
        }
    }

    // MARK: - Маршрутизация

    @Test("Гость читает общую базу и чужую зону, владелец — личную и свою")
    func маршрутРазный() async {
        await какГость {
            #expect(SharedZoneRouting.scope(owner: SharedZoneOwner.name) == .shared)
            #expect(SharedZoneRouting.zone(owner: SharedZoneOwner.name).ownerName == Self.чужой,
                    "Зона гостя адресуется именем ВЛАДЕЛЬЦА. Со своим именем отметки лягут в зону, которой никто не делился.")
        }
        await какВладелец {
            #expect(SharedZoneRouting.scope(owner: SharedZoneOwner.name) == .private)
            #expect(SharedZoneRouting.zone(owner: SharedZoneOwner.name).ownerName == CKCurrentUserDefaultName)
        }
    }

    // MARK: - Запреты. Написаны от обратного: «обязан отказать»

    /// **Здесь стояли два теста, и один из них подделка прошла насквозь.**
    ///
    /// Слабый спрашивал «бросило ли хоть какой-нибудь `ShareError`».
    /// Я снял `guard !isGuest` из `invite` — то есть вернул ровно тот
    /// дефект, ради которого тест и написан, — и он **остался зелёным**:
    /// на симуляторе нет ни профиля, ни аккаунта iCloud, поэтому
    /// `invite` всё равно бросает, только `noEntitlement`. Проверка
    /// выполнялась при противоположном положении дел.
    ///
    /// > То же, что «несошедшийся чек отправляет НЕ ВСЕ строки» у Kvit:
    /// > при нуле не уходит ни одна, и ноль — это тоже «не все».
    /// > **Вопрос был слабее дефекта, который он ищет.**
    ///
    /// Поэтому проверка одна и строгая: отказ обязан быть **именно**
    /// `notOwner`. Это же держит и порядок проверок внутри `invite` —
    /// стоит гостевая позже права или входа, и отказ придёт не про то.
    @Test("Гость не приглашает, и отказ назван своим именем, а не первым попавшимся")
    func гостьНеПриглашает() async throws {
        await какГость {
            do {
                _ = try await FamilyShare.invite(dogName: "Стич")
                Issue.record("Приглашение у гостя прошло — значит второй, пустой дневник снова создаётся в его базе.")
            } catch {
                #expect(FamilyShare.причина(error) == "notOwner",
                        "Пришло «\(FamilyShare.причина(error))» вместо notOwner. Либо запрет гостю снят, либо он стоит позже права и входа — и тогда человек получит совет не про то.")
            }
        }
    }

    /// Та же строгость и по той же причине: «бросило что-нибудь» здесь
    /// выполнялось бы и от `CKError` при отсутствии сети.
    @Test("Гость не прекращает общий доступ: это право владельца")
    func гостьНеПрекращаетОбщийДоступ() async throws {
        await какГость {
            do {
                try await FamilyShare.stopSharing()
                Issue.record("«Перестать делиться» у гостя прошло — значит снова удаляет несуществующее и отвечает успехом.")
            } catch {
                #expect(FamilyShare.причина(error) == "notOwner",
                        "Пришло «\(FamilyShare.причина(error))» вместо notOwner.")
            }
        }
    }

    // MARK: - Граница: кто ещё адресует облако мимо общего адреса

    /// Сторож от ЗАПРЕТА: в `FamilyShare` не должно остаться своей
    /// адресации, кроме как внутри `invite` и помощника `адрес`.
    ///
    /// Считает в исходнике и краснеет на новом месте. Текстовый сторож
    /// ловит «написали мимо» и слеп к «позвали не вовремя» — это его
    /// названная граница, и снимает её только поведенческий тест
    /// с настоящим облаком, которого у нас нет.
    @Test("Никто не адресует базу облака в обход общего адреса")
    func своейАдресацииНеОсталось() throws {
        let исходник = try Self.исходник()

        let строки = исходник.split(separator: "\n").enumerated()
            .map { (номер: $0.offset + 1, текст: String($0.element).trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.текст.hasPrefix("//") && !$0.текст.hasPrefix("///") }

        let прямые = строки.filter {
            $0.текст.contains("container.privateCloudDatabase")
                || $0.текст.contains("container.sharedCloudDatabase")
        }

        #expect(прямые.count > 0,
                "Ноль найденных обращений — это про сканер, а не про код: ищем не ту строку.")

        // Разрешено ровно два: внутри `адрес` (обе ветки) и одно
        // в `invite`, где владелец по построению.
        #expect(прямые.count <= 3,
                "Прямых обращений к базе \(прямые.count) на строках \(прямые.map(\.номер)). Каждое новое — место, где гость снова уедет в свою базу.")
    }

    private static func исходник() throws -> String {
        let тест = URL(fileURLWithPath: #filePath)
        let корень = тест.deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: корень
                .appendingPathComponent("TogoShared")
                .appendingPathComponent("Sync")
                .appendingPathComponent("FamilyShare.swift"),
            encoding: .utf8)
    }
}
