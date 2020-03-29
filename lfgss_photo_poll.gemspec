require_relative 'lib/lfgss_photo_poll/version'

Gem::Specification.new do |spec|
	spec.name          = "lfgss_photo_poll"
	spec.version       = LfgssPhotoPoll::VERSION
	spec.authors       = ["cyclotron3k"]
	spec.email         = ["aidan.samuel@gmail.com"]

	spec.summary       = 'Process posts in the weekly photography thread'
	spec.homepage      = "https://github.com/cyclotron3k/lfgss-photo-poll"
	spec.license       = "MIT"
	spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

	spec.metadata["allowed_push_host"] = 'http://rubygems.com'

	spec.metadata["homepage_uri"] = spec.homepage
	spec.metadata["source_code_uri"] = "https://github.com/cyclotron3k/lfgss-photo-poll"
	# spec.metadata["changelog_uri"] = "https://github.com/cyclotron3k/lfgss-photo-poll"

	spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
		`git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
	end
	spec.bindir        = "exe"
	spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
	spec.require_paths = ["lib"]

	spec.add_runtime_dependency 'nokogiri', '~> 1.10'
	spec.add_runtime_dependency 'mechanize', '~> 2.7'
	spec.add_runtime_dependency 'pushover', '~> 3.0'

	spec.add_development_dependency 'pry', '~> 0.12'
	spec.add_development_dependency 'webmock', '~> 2.3'
	spec.add_development_dependency 'bundler-audit', '~> 0.6'

end
