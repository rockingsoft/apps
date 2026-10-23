require 'xcodeproj'
project = Xcodeproj::Project.new('Garage.xcodeproj')
target = project.new_target(:application, 'Garage', :ios, '17.0')
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
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_CKSharingSupported'] = 'YES'
  config.build_settings['INFOPLIST_KEY_NSLocationWhenInUseUsageDescription'] = 'Garage usa tu ubicación para sugerir la estación al registrar una carga de nafta.'
  config.build_settings['INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription'] = 'Si activás los avisos de cargas, Garage detecta paradas en estaciones incluso con la app cerrada.'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Garage.entitlements'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App/Garage-Release.entitlements' if config.name == 'Release'
  config.build_settings['MARKETING_VERSION'] = '1.0.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['VERSIONING_SYSTEM'] = 'apple-generic'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
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
