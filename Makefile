# Того · сборка и проверки.
#
# Всё, что делается руками в Xcode, здесь повторяется одной командой —
# чтобы то же самое работало в CI и на чистой машине.

SCHEME      ?= Togo
PROJECT     ?= Togo.xcodeproj
# Имя симулятора прибивать нельзя: обновление Xcode их переименовывает,
# и документированная команда сборки умирает молча. Xcode 27 унёс
# «iPhone 17 Pro» — ровно так это и случилось. UDID ищется в момент
# прогона тем же скриптом, которым уже пользуется CI (ci.yml).
DESTINATION ?= platform=iOS Simulator,id=$$(python3 Tools/ci_simulator.py)
CONFIG      ?= Debug

.DEFAULT_GOAL := help

.PHONY: help
help: ## Показать список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: tokens
tokens: ## Пересобрать токены из DesignTokens/tokens.json
	@python3 Tools/generate_tokens.py
	@python3 Tools/пары_ios.py

.PHONY: figma-check
figma-check: ## Сверить код с тем, что плагин отправит в Figma (имена, значения, code syntax)
	@python3 Tools/сверка_токенов_с_фигмой.py | tail -40
	@python3 Tools/пары_ios.py --проверить

.PHONY: project
project: ## Перегенерировать Togo.xcodeproj и схему
	@python3 Tools/generate_project.py

.PHONY: texts
texts: ## Пересобрать docs/TEXTS.md и каталог строк из исходников
	@python3 Tools/extract_texts.py

.PHONY: loc-export
loc-export: ## Выгрузить XLIFF для переводчика (build/loc/*.xcloc)
	@xcodebuild -project $(PROJECT) -exportLocalizations \
		-localizationPath build/loc \
		-exportLanguage en -exportLanguage fr -exportLanguage uk
	@echo "Отдай переводчику папки в build/loc — они открываются в любом CAT-редакторе"

.PHONY: loc-import
loc-import: ## Влить перевод обратно: make loc-import LOC=build/loc/en.xcloc
	@test -n "$(LOC)" || (echo "Укажи LOC=путь/к/en.xcloc" && exit 1)
	@xcodebuild -project $(PROJECT) -importLocalizations -localizationPath $(LOC)

.PHONY: bootstrap
bootstrap: tokens project ## Собрать проект с нуля после клонирования

.PHONY: build
# Код возврата берётся у самого xcodebuild, а не у хвоста конвейера, —
# и до 09.10.2026 это было написано НИЖЕ, у цели `test`, а здесь
# по-прежнему стоял конвейер:
#
#     @xcodebuild … \
#         -destination "$(DESTINATION)" build | tail -5
#
# `grep` когда-то заменили на `tail`, конец конвейера поменялся, код
# возврата — нет. То есть правило было записано в трёх местах свода
# и нарушено В ПРИМЕРЕ, КОТОРЫЙ ЕГО ОБЪЯСНЯЕТ: предупреждение стояло
# двумя строками ниже дефекта.
#
# Замерено, а не прочитано. Форма воспроизводится игрушкой:
#
#     printf 'A:\n\t@false \\\n\t\t| tail -5\n' > /tmp/d.mk
#     make -f /tmp/d.mk A; echo $$?      →  0  на УПАВШЕЙ команде
#
# `pipefail` здесь не годится: `make` зовёт `/bin/sh`, а `pipefail`
# не POSIX — он либо будет проигнорирован, либо даст отказ, и оба
# исхода хуже отсутствия правки. Поэтому лог плюс `rc=$$?` плюс
# `exit $$rc`, ровно как у `test` ниже.
#
# Лог с датой и PID, а не фиксированный: над одним деревом работают
# несколько сессий, и 28.09 в общем файле уже поймали два разных PID —
# кто прочтёт хвост, возьмёт чужой зелёный за свой.
build: ## Собрать приложение под симулятор
	@mkdir -p build/logs
	@LOG=build/logs/build-$$(date +%Y%m%d-%H%M%S)-$$$$.log; \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "$(DESTINATION)" build > $$LOG 2>&1; rc=$$?; \
		tail -5 $$LOG; \
		echo "xcodebuild: код возврата $$rc (полный лог — $$LOG)"; exit $$rc

#
# Читать в выводе нужно строку «✔ Test run with N tests in M suites passed»:
# тесты написаны на Swift Testing, и xcodebuild в конце честно печатает
# «Executed 0 tests» — XCTest-ов в наборе нет. Эту строку читать нельзя.
# Лог у каждого прогона свой, и путь печатается.
#
# Раньше здесь стоял фиксированный `build/unit.log`. Над одним деревом
# работают несколько сессий сразу, и 28.09 в этом файле поймали два
# разных PID `xcodebuild`: чужой `** TEST SUCCEEDED **` от прогона
# в 07:31 лежал ровно там, где следующий начал искать свой. **Кто
# прочтёт хвост, возьмёт чужой зелёный за свой** — а весь метод
# проекта стоит на том, что зелёный указывает на коммит.
#
# DerivedData оставлена общей нарочно: своя на прогон — это полная
# пересборка каждый раз. Разводить сессиям — через `DERIVED=…`.
DERIVED ?= build/DerivedData

.PHONY: test
test: ## Прогнать модульные и UI-тесты
	@mkdir -p build/logs
	@LOG=build/logs/test-$$(date +%Y%m%d-%H%M%S)-$$$$.log; \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath "$(DERIVED)" \
		-destination "$(DESTINATION)" test > $$LOG 2>&1; rc=$$?; \
		grep -E "Test run|error:|\*\* TEST|Restarting after unexpected exit|ВЫЧИТКА:" $$LOG || true; \
		echo "xcodebuild: код возврата $$rc (полный лог — $$LOG)"; exit $$rc

.PHONY: unit
unit: ## Только модульные тесты — быстрая обратная связь (решает сверка с эталоном)
# Бандл результата, а не только лог. Имена упавших сверка берёт
# из структуры: печать их портит (07.10.2026 — один байт кириллицы
# уехал восьмеричным escape в сводной строке, и сверка доложила
# фантомную регрессию). Лог при этом обязателен и дальше: по нему
# и только по нему видно, СОСТОЯЛСЯ ли прогон.
#
# Путь бандла — с PID, как у лога: сессий на этом дереве несколько,
# и общий путь отдавал бы одной сессии результат другой.
#
# Код возврата у цели — питоновский, НЕ xcodebuild. Это нарочно:
# решает сверка с эталоном, а не 65 от трёх ожидаемо красных.
# Но означает, что «exit 0» у вызывающего не равен зелёному прогону, —
# приёмку снимать с текста, строка про код возврата печатается выше.
	@mkdir -p build/logs
	@LOG=build/logs/unit-$$(date +%Y%m%d-%H%M%S)-$$$$.log; \
		BUNDLE=build/unit-$$$$.xcresult; rm -rf $$BUNDLE; \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath "$(DERIVED)" -resultBundlePath $$BUNDLE \
		-destination "$(DESTINATION)" test -only-testing:TogoTests > $$LOG 2>&1; rc=$$?; \
		grep -E "Test run|✘|error:|\*\* TEST|Restarting after unexpected exit|ВЫЧИТКА:" $$LOG || true; \
		echo "xcodebuild: код возврата $$rc (полный лог — $$LOG)"; \
		python3 Tools/сверить_эталон.py --лог $$LOG --бандл $$BUNDLE

.PHONY: device
device: ## Поставить на подключённый iPhone: make device TEAM=XXXXXXXXXX [PERSONAL=1]
	@test -n "$(TEAM)" || (echo "Укажи TEAM=... — id команды из Xcode → Settings → Accounts" && exit 1)
	@PERSONAL="$(PERSONAL)" bash Tools/install_device.sh "$(TEAM)"

.PHONY: archive
archive: ## Собрать архив для App Store Connect
	@# Номер сборки берётся из Tools/номер-сборки.txt через скрипт —
	@# ОДНА дорога к этому числу на три файла.
	@#
	@# Без номера архив получал BUILD_NUMBER = 1 из xcconfig: собирался
	@# успешно и был непригоден, потому что номер обязан расти от загрузки
	@# к загрузке. Узнать об этом на шаге загрузки — потерять сборку зря.
	@#
	@# Прежде здесь стояло `git rev-list --count HEAD`, и 07.10.2026 это
	@# дало бы 506 при 271 в ASC — прыжок на 235 номеров, необратимый:
	@# вернуться к 274 после 506 нельзя уже никогда. Счёт коммитов мерит
	@# количество нашей работы, а номер сборки — количество отданных
	@# сборок, и это разные величины.
	@#
	@# Подстановку нельзя оставлять внутри строки xcodebuild: отказ
	@# скрипта дал бы ПУСТОЙ номер и успешную сборку. Поэтому номер
	@# добывается отдельным шагом с `|| exit 1` и печатается — читатель
	@# лога видит, с каким числом собрано, не разбирая рецепт.
	@BUILD="$$(bash Tools/номер-сборки.sh)" || exit 1; \
	echo "Номер сборки: $$BUILD (Tools/номер-сборки.txt)"; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath build/Togo.xcarchive \
		-allowProvisioningUpdates \
		BUILD_NUMBER="$$BUILD" \
		archive
	@# Языки считаются в КАЖДОМ бандле архива, включая PlugIns/*.appex.
	@# Паспорт архива 216 говорил «fr ru uk внутри бандла» — считали
	@# в Togo.app, а в бандле виджета не было ни одной .lproj. Проверка
	@# стоит здесь, а не в тестах: последнее звено — то, что уедет.
	@bash Tools/check_bundle_languages.sh build/Togo.xcarchive
	@# Витрина обещает языки описаниями, а Apple берёт языки приложения
	@# из бинарника: два списка, и расходятся они молча. 05.10.2026
	@# локаль `en-US` заведена при нуле английских строк — поймать это
	@# было нечем. Проверка стоит здесь же, на последнем звене.
	@python3 Tools/check_storefront_languages.py \
		build/Togo.xcarchive/Products/Applications/Togo.app
	@echo "Собрано: $(SCHEME) $$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw build/Togo.xcarchive/Info.plist) ($$(plutil -extract ApplicationProperties.CFBundleVersion raw build/Togo.xcarchive/Info.plist))"
	@echo "Загружает в TestFlight Tools/upload_testflight.sh — он архивирует сам."

.PHONY: guard
guard: ## Проверить сторожа подделкой в отдельном дереве (ФАЙЛ, БЫЛО, СТАЛО, НАБОР)
	@test -n "$(ФАЙЛ)" || (echo "Как звать: make guard ФАЙЛ=… БЫЛО=… СТАЛО=… НАБОР=TogoTests/XTests" && exit 1)
	@python3 Tools/check_guard.py --файл "$(ФАЙЛ)" --было "$(БЫЛО)" --стало "$(СТАЛО)" --набор "$(НАБОР)"

.PHONY: tokens-check
tokens-check: ## Проверить, что сгенерированные токены не расходятся с tokens.json
	@python3 Tools/generate_tokens.py >/dev/null
	@python3 Tools/пары_ios.py >/dev/null
	@git diff --quiet -- TogoShared/Generated DesignTokens/build \
		DesignTokens/ядро-дизайна/figma-plugin/пары-ios.json \
		DesignTokens/ядро-дизайна/figma-plugin/code.js \
		|| (echo "Токены или пары iOS разошлись: запусти make tokens и закоммить результат" && exit 1)
	@echo "Токены и пары iOS совпадают с источником"

.PHONY: journal
journal: ## Завести запись в журнале проекта за сегодня
	@bash Tools/new_journal.sh

.PHONY: beta
beta: ## Отдать последнюю сборку тестировщикам: тексты и раздача своим
	@test -n "$(ASC_ISSUER)" || (echo "Укажи ASC_ISSUER=... — Issuer ID из App Store Connect" && exit 1)
	@bash Tools/publish_beta.sh

.PHONY: site
site: ## Собрать и опубликовать страницы политики и поддержки
	@bash Tools/publish_site.sh

.PHONY: subs
subs: ## Настроить подписки в App Store Connect из subscriptions.json
	@test -n "$(ASC_ISSUER)" || (echo "Укажи ASC_ISSUER=... — Issuer ID из App Store Connect" && exit 1)
	@bash Tools/setup_subscriptions.sh

.PHONY: usage
usage: ## Забрать с телефона журнал действий (что нажимали и чем кончилось)
	@bash Tools/pull_usage_log.sh

.PHONY: clean
clean: ## Убрать артефакты сборки
	@rm -rf build
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean >/dev/null
