require 'xcodeproj'
project = Xcodeproj::Project.new('Garage.xcodeproj')
target = project.new_target(:application, 'Garage', :ios, '17.0')
llama_framework = project.main_group.new_file('build/llama.xcframework')
target.frameworks_build_phase.add_file_reference(llama_framework)
embed_frameworks = target.new_copy_files_build_phase('Embed Frameworks')
embed_frameworks.dst_subfolder_spec = '10'
embed_frameworks.add_file_reference(llama_framework).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
google_config = project.main_group.new_file('App/GoogleConfig.xcconfig')
target.build_configuration_list.build_configurations.each { |config| config.base_configuration_reference = google_config }
project.build_configuration_list.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
end
target.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['DEVELOPMENT_TEAM'] = '3SRDN9365G'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.schoren.garage'
  config.build_settings['PRODUCT_NAME'] = 'Garage'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'App/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Garage.entitlements'
  if config.name == 'Release'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Garage-Release.entitlements'
    config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
  end
  config.build_settings['MARKETING_VERSION'] = '1.0.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end
%w[App Shared].each do |directory|
  group = project.main_group.new_group(directory, directory)
  Dir["#{directory}/*.swift"].sort.each do |file|
    ref = group.new_file(File.basename(file))
    target.source_build_phase.add_file_reference(ref)
  end
end
assets = project.main_group.new_file('App/Assets.xcassets')
target.resources_build_phase.add_file_reference(assets)
project.root_object.attributes['TargetAttributes'] = { target.uuid => { 'DevelopmentTeam' => '3SRDN9365G', 'SystemCapabilities' => { 'com.apple.iCloud' => { 'enabled' => 1 } } } }
project.save
