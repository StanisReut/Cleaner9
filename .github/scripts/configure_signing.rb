#!/usr/bin/env ruby
# Раскладывает подпись по таргетам проекта: каждому свой профиль, свой bundle id.
#
# Ничего не знает ни про приложение, ни про число расширений — всё берёт из
# профилей, которые уже установлены, и из самого проекта. Один таргет, часы,
# виджет, блокировщик звонков — разницы нет.
#
# Почему настройки пишутся в проект, а не передаются аргументами xcodebuild:
# аргумент применяется ко ВСЕМ таргетам графа, включая SPM-зависимости. У них
# автоматическая подпись, и навязанная личность роняет сборку с
# "conflicting provisioning settings". Поэтому — точечно, по таргетам.
#
# Использование: configure_signing.rb <project.xcodeproj> <profiles/manifest.json>

require 'xcodeproj'
require 'json'

# Кодировку задаём явно: под системной ruby окружение бывает US-ASCII, и тогда
# гем падает на первом же файле проекта с "invalid byte sequence".
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

project_path, manifest_path = ARGV
abort('Использование: configure_signing.rb <project.xcodeproj> <manifest.json>') unless project_path && manifest_path

profiles = JSON.parse(File.read(manifest_path))
main = profiles.find { |p| p['is_main'] }
abort('❌ В манифесте нет основного профиля') unless main

release_base = main['bundle_id']
team_id      = main['team_id']
puts "📦 Основной bundle id: #{release_base} (команда #{team_id})"

project = Xcodeproj::Project.open(project_path)

# Подписываем только то, что уходит в архив как отдельный бинарник.
SIGNABLE = %w[
  com.apple.product-type.application
  com.apple.product-type.app-extension
  com.apple.product-type.extensionkit-extension
  com.apple.product-type.watchkit2-app
  com.apple.product-type.watchkit2-extension
  com.apple.product-type.application.watchapp2
].freeze

signable = project.native_targets.select { |t| SIGNABLE.include?(t.product_type) }
abort('❌ В проекте нет ни одного подписываемого таргета') if signable.empty?

# Bundle id таргета в конфигурации Release — то, что лежит в проекте до нашей правки.
def dev_id(target)
  target.build_configurations.each do |c|
    v = c.build_settings['PRODUCT_BUNDLE_IDENTIFIER']
    return v if v && !v.to_s.empty? && !v.to_s.include?('$(')
  end
  nil
end

# Главный таргет ищем по строению, а не по имени: его идентификатор — начало
# идентификаторов всех остальных. Имена таргетов у каждого проекта свои, а это
# правило задано самой Apple: расширение живёт внутри приложения.
ids = signable.to_h { |t| [t, dev_id(t)] }
missing = ids.select { |_, v| v.nil? }.keys
abort("❌ У таргетов не задан PRODUCT_BUNDLE_IDENTIFIER: #{missing.map(&:name).join(', ')}") unless missing.empty?

main_target = signable.find { |t| ids.values.all? { |v| v == ids[t] || v.start_with?("#{ids[t]}.") } }
abort("❌ Не понял, какой таргет основной. Идентификаторы: #{ids.values.join(', ')}") unless main_target

dev_base = ids[main_target]
puts "📦 Основной таргет: #{main_target.name} (#{dev_base})"

# Сопоставляем таргеты с профилями. Один способ на все проекты не работает:
# девелоперские идентификаторы в проектах бывают какими угодно — с лишними
# уровнями, с опечатками. Поэтому пробуем по очереди, от точного к грубому.
#
#   1. По суффиксу: com.dev.app.widget при основном com.dev.app → «.widget».
#   2. По имени таргета: хвост профиля CallsBlockerExtension = имя таргета.
#   3. По остатку: если не разобран ровно один таргет и ровно один профиль,
#      это они и есть.
#
# Идентификатор таргету ставим из профиля, а не из проекта: профиль — то, что
# признаёт Apple, и он же чинит опечатку, если она была в проекте.
def norm(value)
  value.to_s.downcase.gsub(/[^a-z0-9]/, '')
end

taken = {}
unmatched = []

signable.each do |target|
  suffix = ids[target] == dev_base ? '' : ids[target].sub(/\A#{Regexp.escape(dev_base)}/, '')
  found  = profiles.find { |p| p['bundle_id'] == "#{release_base}#{suffix}" && !taken.value?(p) }
  found ||= profiles.find do |p|
    !taken.value?(p) && !p['is_main'] &&
      norm(p['bundle_id'].split('.').last) == norm(target.name)
  end

  if found
    taken[target] = found
  else
    unmatched << target
  end
end

# По остатку — только когда сомнений быть не может.
left = profiles.reject { |p| taken.value?(p) }
if unmatched.size == 1 && left.size == 1
  puts "ℹ️  '#{unmatched.first.name}' сопоставлен с '#{left.first['name']}' по остатку"
  taken[unmatched.shift] = left.first
end

unless unmatched.empty?
  have = profiles.map { |p| p['bundle_id'] }.join(', ')
  abort("❌ Не подобрал профиль для: #{unmatched.map(&:name).join(', ')}\n" \
        "   Есть профили на: #{have}\n" \
        "   Добавь секрет APPSTORE_CONNECT_PROVISIONING_PROFILE_<ИМЯ> с нужным профилем.")
end

assigned = 0
taken.each do |target, profile|
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER']      = profile['bundle_id']
    config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = profile['uuid']
    config.build_settings['CODE_SIGN_STYLE']                = 'Manual'
    config.build_settings['CODE_SIGN_IDENTITY']             = 'Apple Distribution'
    config.build_settings['DEVELOPMENT_TEAM']               = team_id
  end
  puts "✅ #{target.name} → #{profile['bundle_id']} — профиль '#{profile['name']}'"
  assigned += 1
end

# App group — как bundle id: берём ту, на которую выписан профиль.
#
# В проектах часто стоит шаблонная группа (group.com.template.use…), а профиль
# выписан на релизную. С шаблонной codesign откажет: группы нет в профиле.
# Подменяем, только когда ответ однозначен — у таргета ровно одна группа,
# которой нет в профиле, и в профиле ровно одна, которую таргет не просит.
# Иначе гадать нельзя: подпишем не той группой, и общие данные приложения
# и виджета молча разъедутся. Тогда останавливаемся с понятной причиной.
#
# Ту же строку меняем и в исходниках: если код открывает контейнер по старому
# имени, в релизе он получил бы nil. Правка живёт только на раннере.
project_dir  = File.dirname(project_path)
group_map    = {}
group_errors = []
seen_files   = {}

def entitlements_path(target)
  release = target.build_configurations.find { |c| c.name == 'Release' }
  [release, *target.build_configurations].compact.each do |c|
    v = c.build_settings['CODE_SIGN_ENTITLEMENTS']
    return v.to_s if v && !v.to_s.empty?
  end
  nil
end

taken.each do |target, profile|
  relative = entitlements_path(target)
  next unless relative

  full = File.join(project_dir, relative.gsub('$(SRCROOT)/', ''))
  next unless File.exist?(full)

  plist   = Xcodeproj::Plist.read_from_path(full)
  wanted  = Array(plist['com.apple.security.application-groups']).reject { |g| g.include?('$(') }
  allowed = Array(profile['app_groups'])
  missing = wanted - allowed
  next if missing.empty?

  free = allowed - wanted
  if missing.size == 1 && free.size == 1
    old, new = missing.first, free.first
    if group_map[old] && group_map[old] != new
      group_errors << "#{target.name}: #{old} просится и в #{group_map[old]}, и в #{new}"
      next
    end
    group_map[old] = new
    plist['com.apple.security.application-groups'] =
      Array(plist['com.apple.security.application-groups']).map { |g| g == old ? new : g }
    Xcodeproj::Plist.write_to_path(plist, full)
    puts "👥 #{target.name}: app group #{old} → #{new}" unless seen_files[full]
    seen_files[full] = true
  else
    group_errors << "#{target.name}: в entitlements #{missing.join(', ')}, " \
                    "в профиле '#{profile['name']}' — #{allowed.empty? ? 'ни одной группы' : allowed.join(', ')}"
  end
end

unless group_errors.empty?
  abort("❌ App group не сходится с профилем, а однозначной замены нет:\n   " +
        group_errors.join("\n   ") +
        "\n   Перевыпусти профиль с нужной группой или поправь entitlements.")
end

unless group_map.empty?
  sources = Dir.glob(File.join(project_dir, '**', '*.{swift,m,mm,h,plist,xcconfig}'))
               .reject { |f| f.include?('/Pods/') || f.include?('/.build/') || f.include?('/SourcePackages/') }
  sources.each do |file|
    text = File.read(file, encoding: 'UTF-8') rescue next
    patched = group_map.reduce(text) { |acc, (old, new)| acc.gsub("\"#{old}\"", "\"#{new}\"").gsub(">#{old}<", ">#{new}<") }
    next if patched == text
    File.write(file, patched)
    puts "👥 #{file.sub("#{project_dir}/", '')}: имя группы заменено"
  end
end

# Часы объявляют родителя у себя в Info.plist. Мы только что сменили bundle id
# приложения — без этой правки пара «приложение + часы» не считается связанной,
# и архив падает уже на валидации.
WATCH_TYPES = %w[
  com.apple.product-type.watchkit2-app
  com.apple.product-type.application.watchapp2
].freeze

watch_done = []
signable.each do |target|
  next unless WATCH_TYPES.include?(target.product_type) ||
              (target.product_type == 'com.apple.product-type.application' && target != main_target)

  target.build_configurations.each do |config|
    if config.build_settings.key?('INFOPLIST_KEY_WKCompanionAppBundleIdentifier')
      config.build_settings['INFOPLIST_KEY_WKCompanionAppBundleIdentifier'] = release_base
      puts "⌚️ #{target.name}: родитель прописан настройкой сборки"
    end

    path = config.build_settings['INFOPLIST_FILE']
    next if path.nil? || path.to_s.empty?

    full = File.join(File.dirname(project_path), path.to_s.gsub('$(SRCROOT)/', ''))
    next unless File.exist?(full)

    plist = Xcodeproj::Plist.read_from_path(full)
    next unless plist.key?('WKCompanionAppBundleIdentifier')

    plist['WKCompanionAppBundleIdentifier'] = release_base
    Xcodeproj::Plist.write_to_path(plist, full)
    next if watch_done.include?(full)
    watch_done << full
    puts "⌚️ #{target.name}: родитель прописан в #{path}"
  end
end

project.save
puts "✅ Настроено таргетов: #{assigned}"
