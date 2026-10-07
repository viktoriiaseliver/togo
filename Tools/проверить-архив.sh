#!/bin/bash
# Проверка файла архива НАСТОЯЩИМ BackupArchive, а не глазами.
#   bash Tools/проверить-архив.sh <файл.togo>
# Собирает BackupArchive.swift отдельным бинарём: Xcode и симулятор не нужны.
set -uo pipefail
[ $# -eq 1 ] || { echo "нужен путь к файлу архива"; exit 2; }
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
sed 's/^import SwiftData$/\/\/&/; s/^import UniformTypeIdentifiers$/\/\/&/; s/^import CoreTransferable$/\/\/&/' \
  "$REPO/TogoShared/Domain/BackupArchive.swift" > "$W/BackupArchive.swift"
# DoseSlot живёт в Models/Care.swift рядом с @Model-классами — тянуть весь файл
# значило бы тянуть SwiftData. Повторён здесь ровно той же формы.
cat > "$W/DoseSlot.swift" <<'SW'
import Foundation
nonisolated struct DoseSlot: Codable, Hashable, Sendable {
    var minuteOfDay: Int
    var quantity: Double
}
SW
cat > "$W/main.swift" <<'SW'
import Foundation
let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
do {
  let a = try dec.decode(BackupArchive.self, from: data)
  let w = a.dogs.reduce(0) { $0 + $1.weights.count }
  let m = a.dogs.reduce(0) { $0 + $1.medications.count }
  let c = a.dogs.reduce(0) { $0 + $1.careTasks.count }
  print("ПРИНЯТ: formatVersion=\(a.formatVersion) собак=\(a.dogs.count) участников=\(a.members.count) эпизодов=\(a.episodes.count) весов=\(w) лекарств=\(m) задач=\(c)")
} catch { print("ОТКАЗ: \(error)"); exit(1) }
SW
swiftc -O "$W/BackupArchive.swift" "$W/DoseSlot.swift" "$W/main.swift" -o "$W/decode" || { echo "не собралось"; exit 1; }
"$W/decode" "$1"
