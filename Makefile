# Того · сборка и проверки.
#
# Всё, что делается руками в Xcode, здесь повторяется одной командой —
# чтобы то же самое работало в CI и на чистой машине.

SCHEME      ?= Togo
PROJECT     ?= Togo.xcodeproj
DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
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
		-destination '$(DESTINATION)' build | tail -5

.PHONY: test
test: ## Прогнать модульные и UI-тесты
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination '$(DESTINATION)' test | grep -E "Test run|Executed|error:|\*\* TEST"

.PHONY: unit
unit: ## Только модульные тесты — быстрая обратная связь
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination '$(DESTINATION)' test -only-testing:TogoTests \
		| grep -E "Test run|✘|error:"

.PHONY: device
device: ## Поставить на подключённый iPhone: make device TEAM=XXXXXXXXXX
	@test -n "$(TEAM)" || (echo "Укажи TEAM=... — id команды из Xcode → Settings → Accounts" && exit 1)
	@bash Tools/install_device.sh "$(TEAM)"

.PHONY: archive
archive: ## Собрать архив для App Store Connect
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath build/Togo.xcarchive archive

.PHONY: tokens-check
tokens-check: ## Проверить, что сгенерированные токены не расходятся с tokens.json
	@python3 Tools/generate_tokens.py >/dev/null
	@git diff --quiet -- TogoShared/Generated DesignTokens/build \
		|| (echo "Токены разошлись: запусти make tokens и закоммить результат" && exit 1)
	@echo "Токены совпадают с источником"

.PHONY: journal
journal: ## Завести запись в журнале проекта за сегодня
	@bash Tools/new_journal.sh

.PHONY: usage
usage: ## Забрать с телефона журнал действий (что нажимали и чем кончилось)
	@bash Tools/pull_usage_log.sh

.PHONY: clean
clean: ## Убрать артефакты сборки
	@rm -rf build
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean >/dev/null
