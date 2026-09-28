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

.PHONY: project
project: ## Перегенерировать Togo.xcodeproj и схему
	@python3 Tools/generate_project.py

.PHONY: texts
texts: ## Пересобрать docs/TEXTS.md и каталог строк из исходников
	@python3 Tools/extract_texts.py

.PHONY: loc-export
loc-export: ## Выгрузить XLIFF для переводчика (build/loc/*.xcloc)
	@xcodebuild -project $(PROJECT) -exportLocalizations \
		-localizationPath build/loc -exportLanguage en -exportLanguage fr
	@echo "Отдай переводчику папки в build/loc — они открываются в любом CAT-редакторе"

.PHONY: loc-import
loc-import: ## Влить перевод обратно: make loc-import LOC=build/loc/en.xcloc
	@test -n "$(LOC)" || (echo "Укажи LOC=путь/к/en.xcloc" && exit 1)
	@xcodebuild -project $(PROJECT) -importLocalizations -localizationPath $(LOC)

.PHONY: bootstrap
bootstrap: tokens project ## Собрать проект с нуля после клонирования

.PHONY: build
build: ## Собрать приложение под симулятор
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "$(DESTINATION)" build | tail -5

# Код возврата берётся у самого xcodebuild, а не у хвоста конвейера.
# Раньше здесь стоял `xcodebuild … | grep …`, и наружу уходил код grep:
# прогон падал, а команда отвечала нулём. На этом сгорели дважды за день.
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
		grep -E "Test run|error:|\*\* TEST|Restarting after unexpected exit" $$LOG || true; \
		echo "xcodebuild: код возврата $$rc (полный лог — $$LOG)"; exit $$rc

.PHONY: unit
unit: ## Только модульные тесты — быстрая обратная связь
	@mkdir -p build/logs
	@LOG=build/logs/unit-$$(date +%Y%m%d-%H%M%S)-$$$$.log; \
		xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath "$(DERIVED)" \
		-destination "$(DESTINATION)" test -only-testing:TogoTests > $$LOG 2>&1; rc=$$?; \
		grep -E "Test run|✘|error:|\*\* TEST|Restarting after unexpected exit" $$LOG || true; \
		echo "xcodebuild: код возврата $$rc (полный лог — $$LOG)"; exit $$rc

.PHONY: device
device: ## Поставить на подключённый iPhone: make device TEAM=XXXXXXXXXX [PERSONAL=1]
	@test -n "$(TEAM)" || (echo "Укажи TEAM=... — id команды из Xcode → Settings → Accounts" && exit 1)
	@PERSONAL="$(PERSONAL)" bash Tools/install_device.sh "$(TEAM)"

.PHONY: archive
archive: ## Собрать архив для App Store Connect
	@# Номер сборки — количество коммитов, как в Tools/upload_testflight.sh.
	@# Без него архив получал BUILD_NUMBER = 1 из xcconfig: собирался
	@# успешно и был непригоден, потому что номер обязан расти от загрузки
	@# к загрузке. Узнать об этом на шаге загрузки — потерять сборку зря.
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath build/Togo.xcarchive \
		-allowProvisioningUpdates \
		BUILD_NUMBER="$$(git rev-list --count HEAD)" \
		archive
	@# Языки считаются в КАЖДОМ бандле архива, включая PlugIns/*.appex.
	@# Паспорт архива 216 говорил «fr ru uk внутри бандла» — считали
	@# в Togo.app, а в бандле виджета не было ни одной .lproj. Проверка
	@# стоит здесь, а не в тестах: последнее звено — то, что уедет.
	@bash Tools/check_bundle_languages.sh build/Togo.xcarchive
	@echo "Собрано: $(SCHEME) $$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw build/Togo.xcarchive/Info.plist) ($$(plutil -extract ApplicationProperties.CFBundleVersion raw build/Togo.xcarchive/Info.plist))"
	@echo "Загружает в TestFlight Tools/upload_testflight.sh — он архивирует сам."

.PHONY: guard
guard: ## Проверить сторожа подделкой в отдельном дереве (ФАЙЛ, БЫЛО, СТАЛО, НАБОР)
	@test -n "$(ФАЙЛ)" || (echo "Как звать: make guard ФАЙЛ=… БЫЛО=… СТАЛО=… НАБОР=TogoTests/XTests" && exit 1)
	@python3 Tools/check_guard.py --файл "$(ФАЙЛ)" --было "$(БЫЛО)" --стало "$(СТАЛО)" --набор "$(НАБОР)"

.PHONY: tokens-check
tokens-check: ## Проверить, что сгенерированные токены не расходятся с tokens.json
	@python3 Tools/generate_tokens.py >/dev/null
	@git diff --quiet -- TogoShared/Generated DesignTokens/build \
		|| (echo "Токены разошлись: запусти make tokens и закоммить результат" && exit 1)
	@echo "Токены совпадают с источником"

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
