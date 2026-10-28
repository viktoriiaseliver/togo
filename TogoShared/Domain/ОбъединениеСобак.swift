import Foundation
import SwiftData

/// Перенос записей с одной карточки собаки на другую — одно место.
///
/// # Почему отдельный тип, а не метод отладочного инструмента
///
/// Замер 28.10.2026. Слияние дубликатов было написано ДВАЖДЫ:
///
/// ```
/// Togo/Store/DuplicateMerge.swift      под `#if DEBUG` — кнопка «Отладка»
/// Togo/Features/Family/DuplicateDogCard.swift   РЕЛИЗНЫЙ экран «Семья»
/// ```
///
/// Разные условия компиляции — вот почему копия и завелась: экран
/// не может звать то, чего в релизе нет. А счёт переносимого жил
/// третьей и четвёртой копией рядом с каждым переносом.
///
/// # Все четыре копии были неполны ОДИНАКОВО
///
/// Связей «ко многим» у `Dog` **пятнадцать**, переносилось
/// **одиннадцать**. Не переносились:
///
/// ```
/// labResultsStorage      анализы        у Стича 140 записей
/// vetVisitsStorage       визиты                   40
/// prescriptionsStorage   рецепты                  40
/// diagnosesStorage       диагнозы                  7
/// ```
///
/// Удаление лишней собаки мягкое — надгробие `deletedAt`, а не
/// `context.delete`, — поэтому записи физически целы и `.cascade`
/// не срабатывает. Но они остаются привязанными к собаке
/// С НАДГРОБИЕМ, а медицинский слой показывает записи активной:
/// двести двадцать семь записей исчезали со всех экранов.
///
/// > Человек жмёт «слить дубликаты», теряет из виду всю медицинскую
/// > историю и читает «Перенесено записей: N. Дневник снова один».
/// > Число при этом честное — оно считалось по тому же неполному
/// > списку, что и перенос.
///
/// # Полноту списка сторожит тест, а не внимательность
///
/// `СлияниеПереноситВсёTests` читает связи прямо из описания модели
/// и требует, чтобы каждая была названа здесь. Новая связь у `Dog`
/// покраснеет сразу, а не потеряется при первом слиянии у человека.
nonisolated enum ОбъединениеСобак {

    /// Перенести все записи лишней карточки на главную.
    ///
    /// - Returns: сколько записей переехало. Считается ДО переноса
    ///   и тем же списком — иначе число в подтверждении разошлось бы
    ///   с тем, что на самом деле случилось.
    @discardableResult
    static func перенести(с лишняя: Dog, на главная: Dog) -> Int {
        let сколько = связанных(лишняя)
        лишняя.eventsStorage?.forEach { $0.dog = главная }
        лишняя.weightsStorage?.forEach { $0.dog = главная }
        лишняя.careTasksStorage?.forEach { $0.dog = главная }
        лишняя.medicationsStorage?.forEach { $0.dog = главная }
        лишняя.trainingStepsStorage?.forEach { $0.dog = главная }
        лишняя.trainingSessionsStorage?.forEach { $0.dog = главная }
        лишняя.tripsStorage?.forEach { $0.dog = главная }
        лишняя.documentsStorage?.forEach { $0.dog = главная }
        лишняя.daysOutStorage?.forEach { $0.dog = главная }
        лишняя.heatsStorage?.forEach { $0.dog = главная }
        лишняя.stocksStorage?.forEach { $0.dog = главная }
        // Четыре связи медицинского слоя, которых не переносил никто.
        лишняя.labResultsStorage?.forEach { $0.dog = главная }
        лишняя.vetVisitsStorage?.forEach { $0.dog = главная }
        лишняя.diagnosesStorage?.forEach { $0.dog = главная }
        лишняя.prescriptionsStorage?.forEach { $0.dog = главная }
        return сколько
    }

    /// Сколько записей висит на карточке.
    ///
    /// Тот же список, что у переноса, и это не дублирование внутри
    /// одного типа: счёт обязан совпадать с тем, что переносится.
    /// Разъехались бы они — и подтверждение врало бы человеку
    /// о собственных данных.
    static func связанных(_ собака: Dog) -> Int {
        var всего = 0
        всего += собака.eventsStorage?.count ?? 0
        всего += собака.weightsStorage?.count ?? 0
        всего += собака.careTasksStorage?.count ?? 0
        всего += собака.medicationsStorage?.count ?? 0
        всего += собака.trainingStepsStorage?.count ?? 0
        всего += собака.trainingSessionsStorage?.count ?? 0
        всего += собака.tripsStorage?.count ?? 0
        всего += собака.documentsStorage?.count ?? 0
        всего += собака.daysOutStorage?.count ?? 0
        всего += собака.heatsStorage?.count ?? 0
        всего += собака.stocksStorage?.count ?? 0
        всего += собака.labResultsStorage?.count ?? 0
        всего += собака.vetVisitsStorage?.count ?? 0
        всего += собака.diagnosesStorage?.count ?? 0
        всего += собака.prescriptionsStorage?.count ?? 0
        return всего
    }

    /// Имена связей, которые перенос обязан трогать.
    ///
    /// Нужны стражу: он сверяет этот список с описанием модели
    /// и краснеет, когда у `Dog` появляется связь, которой здесь нет.
    /// Список написан рукой НАРОЧНО — вывести его из модели значило бы
    /// проверять код им же самим, и сторож зеленел бы на любой дыре.
    static let переносимые: Set<String> = [
        "eventsStorage", "weightsStorage", "careTasksStorage",
        "medicationsStorage", "trainingStepsStorage", "trainingSessionsStorage",
        "tripsStorage", "documentsStorage", "daysOutStorage",
        "heatsStorage", "stocksStorage", "labResultsStorage",
        "vetVisitsStorage", "diagnosesStorage", "prescriptionsStorage",
    ]
}
