# react-native-riden-ssh.podspec

require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-riden-ssh"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  react-native-riden-ssh
                   DESC
  s.homepage     = "https://github.com/ridenui/react-native-riden-ssh"
  # brief license entry:
  s.license      = "MIT"
  # optional - use expanded license entry instead:
  # s.license    = { :type => "MIT", :file => "LICENSE" }
  s.authors      = { "Nils Bergmann" => "nilsbergmann@noim.io" }
  s.platforms    = { :ios => "9.0" }
  s.source       = { :git => "https://github.com/ridenui/react-native-riden-ssh.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,c,cc,cpp,m,mm,swift}"
  s.exclude_files = "ios/Pods/**/*", "ios/Podfile", "ios/Podfile.lock"
  s.requires_arc = false

  s.dependency "React"
  s.dependency "SwifterSwiftSSH", "~> 1.2.7"
end

