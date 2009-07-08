# CouchSphinx, a full text indexing extension for CouchDB/CouchRest.

Gem::Specification.new do |spec|
  spec.platform = "ruby"
  spec.name = "couchsphinx"
  spec.homepage = "http://github.com/ulbrich/couchsphinx"
  spec.version = "0.2"
  spec.author = "Jan Ulbrich"
  spec.email = "jan.ulbrich @nospam@ holtzbrinck.com"
  spec.summary = "A full text indexing extension for CouchDB/CouchRest."
  spec.files = ["README.rdoc", "couchsphinx.rb", "lib/multi_attribute.rb", "lib/mixins/properties.rb", "lib/mixins/indexer.rb", "lib/indexer.rb"]
  spec.require_path = "."
  spec.has_rdoc = true
  spec.executables = []
  spec.extra_rdoc_files = ["README.rdoc"]
  spec.rdoc_options = ["--exclude", "pkg", "--exclude", "tmp", "--all", "--title", "CouchSphinx", "--main", "README.rdoc"]
end
