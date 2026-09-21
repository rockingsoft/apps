#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'
Dir.chdir(File.expand_path('..', __dir__))
project = Xcodeproj::Project.new('CalendarWidget.xcodeproj')
shared = project.main_group.new_group('Shared', 'Shared')
app_group = project.main_group.new_group('App', 'App')
widget_group = project.main_group.new_group('Widget', 'Widget')
shared_files = Dir['Shared/*.swift'].map { |path| shared.new_file(File.basename(path)) }
app_files = Dir['App/*.swift'].map { |path| app_group.new_file(File.basename(path)) }
widget_files = Dir['Widget/*.swift'].map { |path| widget_group.new_file(File.basename(path)) }
[['Mac', :osx, '14.0'], ['iOS', :ios, '17.0']].each do |suffix, platform, deployment|
  app = project.new_target(:application, "Agenda#{suffix}", platform, deployment)
  widget = project.new_target(:app_extension, "AgendaWidget#{suffix}", platform, deployment)
  app.add_file_references(shared_files + app_files)
  widget.add_file_references(shared_files + widget_files)
  [app, widget].each do |target|
    is_widget = target == widget
    target.build_configurations.each do |config|
      settings = config.build_settings
      settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.schoren.calendarwidget#{suffix.downcase}#{is_widget ? '.widget' : ''}"
      settings['SWIFT_VERSION'] = '5.0'
      settings['AGENDA_APP_GROUP'] = platform == :osx ? '$(DEVELOPMENT_TEAM).com.schoren.calendarwidget' : 'group.com.schoren.calendarwidget'
      settings['CODE_SIGN_STYLE'] = 'Automatic'
      settings['GENERATE_INFOPLIST_FILE'] = 'NO'
      settings['INFOPLIST_FILE'] = "#{is_widget ? 'Widget' : 'App'}/Info.plist"
      settings['CODE_SIGN_ENTITLEMENTS'] = "#{is_widget ? 'Widget' : 'App'}/#{suffix}.entitlements"
      settings['CURRENT_PROJECT_VERSION'] = '2'
      settings['MARKETING_VERSION'] = '0.2.0'
      settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'YES'
      settings['TARGETED_DEVICE_FAMILY'] = '1,2' if platform == :ios
      settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' if is_widget
      settings['SKIP_INSTALL'] = 'YES' if is_widget
      settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'] if is_widget
    end
    entitlements = {'com.apple.security.application-groups' => ['$(AGENDA_APP_GROUP)']}
    if platform == :osx
      entitlements['com.apple.security.app-sandbox'] = true
      entitlements['com.apple.security.personal-information.calendars'] = true
    end
    Xcodeproj::Plist.write_to_path(entitlements, "#{is_widget ? 'Widget' : 'App'}/#{suffix}.entitlements")
  end
  app.add_dependency(widget)
  embed = app.new_copy_files_build_phase('Embed App Extensions')
  embed.dst_subfolder_spec = '13'
  embed.add_file_reference(widget.product_reference).settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(app)
  scheme.set_launch_target(app)
  scheme.save_as(project.path, "Agenda#{suffix}", true)
end
base = {
 'AgendaAppGroup' => '$(AGENDA_APP_GROUP)', 'CFBundleDevelopmentRegion' => 'es', 'CFBundleDisplayName' => 'Agenda',
 'CFBundleExecutable' => '$(EXECUTABLE_NAME)', 'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)',
 'CFBundleInfoDictionaryVersion' => '6.0', 'CFBundleName' => '$(PRODUCT_NAME)',
 'CFBundleShortVersionString' => '$(MARKETING_VERSION)', 'CFBundleVersion' => '$(CURRENT_PROJECT_VERSION)',
 'NSCalendarsFullAccessUsageDescription' => 'Agenda necesita leer tus calendarios para mostrar tus eventos en la agenda y los widgets.',
 'NSRemindersFullAccessUsageDescription' => 'Agenda necesita leer tus recordatorios y guardar los que marques como completados.'
}
Xcodeproj::Plist.write_to_path(base.merge('CFBundlePackageType' => 'APPL', 'LSMinimumSystemVersion' => '$(MACOSX_DEPLOYMENT_TARGET)', 'UILaunchScreen' => {}, 'UISupportedInterfaceOrientations' => ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'], 'CFBundleURLTypes' => [{'CFBundleURLName' => 'Agenda', 'CFBundleURLSchemes' => ['calendarwidget']}]), 'App/Info.plist')
Xcodeproj::Plist.write_to_path(base.merge('CFBundlePackageType' => 'XPC!', 'NSExtension' => {'NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension'}), 'Widget/Info.plist')
project.save
