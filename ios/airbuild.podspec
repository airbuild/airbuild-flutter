Pod::Spec.new do |s|
  s.name             = 'airbuild'
  s.version          = '0.1.0'
  s.summary          = 'AirBuild Distribution SDK for Flutter.'
  s.description      = <<-DESC
Check for new binary builds from AirBuild install links and prompt testers to install them.
                       DESC
  s.homepage         = 'https://airbuild.dev'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'AirBuild' => 'support@airbuild.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '11.0'
  s.swift_version    = '5.0'
  s.ios.deployment_target = '11.0'
end
