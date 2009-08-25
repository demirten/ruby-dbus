Gem::Specification.new do |s|
  s.name = %q{ruby-dbus}
  s.version = "0.2.4.5.1"

  s.specification_version = 2 if s.respond_to? :specification_version=

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = "Ruby DBUS Team, pangdudu, demirten"
  s.email = "demirten@github"
  s.homepage = "http://github.com/demirten/ruby-dbus/tree/master"
  s.platform = Gem::Platform::RUBY
  s.date = %q{2009-08-25}
  s.description = %q{Ruby module for interaction with dbus, pangdudu dev fork.}
  s.summary = %q{Ruby module for interaction with dbus.}
  s.files = ["COPYING", "README.rdoc", "lib/dbus", "lib/dbus/message.rb", 
    "lib/dbus/auth.rb", "lib/dbus/marshall.rb", "lib/dbus/export.rb", 
    "lib/dbus/type.rb", "lib/dbus/introspect.rb", "lib/dbus/matchrule.rb",
    "lib/dbus/bus.rb", "lib/dbus.rb",
    "config/remote.session.dbus.conf","config/start_dbus_session.sh",
    "test/simple_socket_test.rb"]
  s.has_rdoc = true
  s.extra_rdoc_files = ["README.rdoc","COPYING"]
  s.autorequire = "dbus"
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.add_dependency(%q<pangdudu-rofl>, [">= 0"])
  s.add_dependency(%q<hpricot>, [">= 0"])
end
