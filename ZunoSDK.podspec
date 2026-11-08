Pod::Spec.new do |s|
  s.name         = 'ZunoSDK'
  s.version      = '0.1.0'
  s.summary      = 'Swift client for the Zuno developer delivery API.'
  s.description  = <<-DESC
    Quotes, order creation with idempotency keys, order and status reads, polling status stream,
    cancellation, driver contact, rider chat, GhanaPostGPS and tracking-number lookup. Talks to
    your own backend proxy, which holds the tenant API key.
  DESC
  s.homepage     = 'https://github.com/fening/zuno-ios-sdk'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = 'Zuno contributors'
  s.source       = { :git => 'https://github.com/fening/zuno-ios-sdk.git', :tag => s.version.to_s }
  s.documentation_url = 'https://developers.zunodelivery.com/docs/mobile-sdks'

  s.platform     = :ios, '15.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/ZunoSDK/**/*.swift'
end
