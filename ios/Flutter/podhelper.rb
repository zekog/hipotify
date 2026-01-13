# This file is a loader for the real podhelper.rb located in the Flutter SDK.
# It dynamically finds the FLUTTER_ROOT from Generated.xcconfig.

def flutter_root
  generated_xcconfig_path = File.expand_path(File.join('..', '..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcconfig_path)
    raise "Generated.xcconfig not found at #{generated_xcconfig_path}. Run 'flutter pub get' or 'flutter build ios' first."
  end

  File.foreach(generated_xcconfig_path) do |line|
    matches = line.match(/\s*FLUTTER_ROOT\s*=\s*(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in Generated.xcconfig"
end

podhelper_path = File.join(flutter_root, 'packages', 'flutter_tools', 'bin', 'podhelper.rb')
unless File.exist?(podhelper_path)
  raise "podhelper.rb not found at #{podhelper_path}"
end

load podhelper_path
