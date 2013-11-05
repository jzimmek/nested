Gem::Specification.new do |s|
  s.name               = "nested"
  s.version            = "0.0.8"

  s.authors = ["Jan Zimmek"]
  s.email = %q{jan.zimmek@web.de}

  s.summary = %q{a nestable dsl to create a restful api}
  s.description = %q{a nestable dsl to create a restful api}


  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")

  s.require_paths = ["lib"]

  s.add_runtime_dependency "activesupport"
  s.add_runtime_dependency "activerecord"
  s.add_runtime_dependency "sinatra"
  s.add_runtime_dependency "json"
end