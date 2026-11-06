require 'xcodeproj'
project = Xcodeproj::Project.new('Nido.xcodeproj')
target = project.new_target(:application, 'Nido', :ios, '17.0')
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
  config.build_settings['PRODUCT_NAME'] = 'Nido'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'App/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Nido.entitlements'
  if config.name == 'Release'
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Nido-Release.entitlements'
    config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = '$(NIDO_APP_PROFILE_UUID)'
  end
  config.build_settings['MARKETING_VERSION'] = '1.0.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end
%w[App Shared ControlShared].each do |directory|
  group = project.main_group.new_group(directory, directory)
  Dir["#{directory}/*.swift"].sort.each do |file|
    ref = group.new_file(File.basename(file))
    target.source_build_phase.add_file_reference(ref)
  end
end
assets = project.main_group.new_file('App/Assets.xcassets')
target.resources_build_phase.add_file_reference(assets)
project.root_object.attributes['TargetAttributes'] = { target.uuid => { 'DevelopmentTeam' => '3SRDN9365G', 'SystemCapabilities' => { 'com.apple.iCloud' => { 'enabled' => 1 } } } }
controls = project.new_target(:app_extension, 'NidoControls', :ios, '18.0')
controls.build_configurations.each do |config|
  config.build_settings.merge!({
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '18.0',
    'DEVELOPMENT_TEAM' => '3SRDN9365G',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.schoren.garage.controls',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => 'Controls/Info.plist',
    'MARKETING_VERSION' => '1.0.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'TARGETED_DEVICE_FAMILY' => '1',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES'
  })
  if config.name == 'Release'
    config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = '$(NIDO_CONTROLS_PROFILE_UUID)'
  end
end
control_group = project.main_group.new_group('Controls', 'Controls')
Dir['Controls/*.swift'].sort.each do |file|
  controls.source_build_phase.add_file_reference(control_group.new_file(File.basename(file)))
end
project.main_group['ControlShared'].files.each do |ref|
  controls.source_build_phase.add_file_reference(ref)
end
target.add_dependency(controls)
embed = target.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(controls.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
