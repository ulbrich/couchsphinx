# CouchSphinx, a full text indexing extension for CouchDB/CouchRest.
#
# This file contains the includes implementing this library. Have a look at
# the README.rdoc as a starting point.

require 'rubygems'

require 'couchrest'
require 'riddle'

# Version number to use for updating CouchDB design document CouchSphinxIndex
# if needed.

module CouchSphinx
  if (match = __FILE__.match(/couchsphinx-([0-9.-]*)/))
    VERSION = match[1]
  else
    VERSION = 'unknown'
  end
end

# Require the stuff implementing this library...

require 'lib/multi_attribute'
require 'lib/indexer'
require 'lib/mixins/indexer'
require 'lib/mixins/properties'
