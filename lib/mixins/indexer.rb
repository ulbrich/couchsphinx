# CouchSphinx, a full text indexing extension for CouchDB/CouchRest.
#
# This file contains the CouchRest::Mixins::Indexer module which in turn
# includes CouchRest::Mixins::Indexer::ClassMethods.

# Patches to the CouchRest library.

module CouchRest # :nodoc:
  module Mixins # :nodoc:

    # Mixin for CouchRest adding indexing stuff. See class ClassMethods for
    # details.

    module Indexer #:nodoc:

      # Bootstrap method to include patches with.
      #
      # Parameters:
      #
      # [base] Class to include class methods of module into

      def self.included(base)
        base.extend(ClassMethods)
      end

      # Patches to the CouchRest ExtendedDocument module: Adds the
      # "fulltext_index" method for enabling indexing and defining the fields
      # to include as a domain specific extention. This method also assures
      # the existence of a special design document used to generate indexes
      # from.
      # 
      # An additional save callback sets an ID like "Post-123123" (class name
      # plus pure numeric ID compatible with Sphinx) for new objects).
      #
      # Last but not least method "by_fulltext_index" is defined allowing a
      # full text search like "foo @title bar" within the context of the
      # current class.
      #
      # Samples:
      #
      #   class Post < CouchRest::ExtendedDocument
      #     use_database SERVER.default_database
      # 
      #     property :title
      #     property :body
      #
      #     fulltext_index :title, :body
      #   end
      #
      #   Post.by_fulltext_index('first')
      #   => [...]
      #   post = Post.by_fulltext_index('this is @title post').first
      #   post.title
      #   => "First Post"
      #   post.class
      #   => Post

      module ClassMethods

        # Method for enabling fulltext indexing and for defining the fields to
        # include.
        #
        # Parameters:
        #
        # [keys] Array of field keys to include plus options Hash
        #
        # Options:
        #
        # [:server] Server name (defaults to localhost)
        # [:port] Server port (defaults to 3312)
        # [:idsize] Number of bits for the ID to generate (defaults to 32)

        def fulltext_index(*keys)
          opts = keys.pop if keys.last.is_a?(Hash)
          opts ||= {} # Handle some options: Future use... :-)

          # Save the keys to index and the options for later use in callback.
          # Helper method cattr_accessor is already bootstrapped by couchrest
          # gem. 

          cattr_accessor :fulltext_keys 
          cattr_accessor :fulltext_opts 

          self.fulltext_keys = keys
          self.fulltext_opts = opts

          # We add a few new functions to CouchDB for retrieving modified
          # documents...

          assure_existing_couch_index

          # Overwrite setting of new ID to do something compatible with
          # Sphinx. If an ID already exists, we try to match it with our 
          # Schema and cowardly ignore if not.

          save_callback :before do |object|
            if object.id.nil?
              idsize = fulltext_opts[:idsize] || 32
              limit = (1 << idsize) - 1

              while true
                id = rand(limit)
                candidate = "#{self.class.to_s}-#{id}"

                begin
                  object.class.get(candidate) # Resource not found exception if available
                rescue RestClient::ResourceNotFound
                  object['_id'] = candidate
                  break
                end
              end
            end
          end
        end

        # Searches for an object of this model class (e.g. Post, Comment) and
        # the requested query string. The query string may contain any query 
        # provided by Sphinx.
        #
        # Call CouchRest::ExtendedDocument.by_fulltext_index() to query
        # without reducing to a single class type.
        #
        # Parameters:
        #
        # [query] Query string like "foo @title bar"
        # [options] Additional options to set
        #
        # Options:
        #
        # [:match_mode] Optional Riddle match mode (defaults to :extended)
        # [:limit] Optional Riddle limit (Riddle default)
        # [:max_matches] Optional Riddle max_matches (Riddle default)
        # [:sort_by] Optional Riddle sort order (also sets sort_mode to :extended)
        # [:raw] Flag to return only IDs and do not lookup objects (defaults to false)

        def by_fulltext_index(query, options = {})
          if self == ExtendedDocument
            client = Riddle::Client.new
          else
            client = Riddle::Client.new(fulltext_opts[:server],
                     fulltext_opts[:port])

            query = query + " @couchrest-type #{self}"
          end

          client.match_mode = options[:match_mode] || :extended

          if (limit = options[:limit])
            client.limit = limit
          end

          if (max_matches = options[:max_matches])
            client.max_matches = matches
          end

          if (sort_by = options[:sort_by])
            client.sort_mode = :extended
            client.sort_by = sort_by
          end

          result = client.query(query)

          if result and result[:status] == 0 and (matches = result[:matches])
            keys = matches.collect { |row| (CouchSphinx::MultiAttribute.decode(
                     row[:attributes]['csphinx-class']) +
                     '-' + row[:doc].to_s) rescue nil }.compact

            return keys if options[:raw]
            return multi_get(keys)
          else
            return []
          end
        end

        # Returns objects for all provided keys not reducing lookup to a
        # certain type. Casts to a CouchRest object if possible.
        #
        # Parameters:
        #
        # [ids] Array of document IDs to retrieve

        def multi_get(ids)
          result = CouchRest.post(SERVER.default_database.to_s +
                   '/_all_docs?include_docs=true', :keys => ids)

          return result['rows'].collect { |row|
                   row = row['doc'] if row['couchrest-type'].nil?

                   if row and (class_name = row['couchrest-type'])
                     eval(class_name.to_s).new(row) rescue row
                   else
                     row
                   end
                 }
        end

        # Defines a design document with the functions needed to lookup
        # modified documents. If the current version is to old, a new version 
        # of the design document is stored.

        def assure_existing_couch_index
          if (doc = database.get("_design/CouchSphinxIndex") rescue nil)
            return if (ver = doc['version']) and ver == CouchSphinx::VERSION

            database.delete_doc(doc)
          end

          all_couchrests = {
            :map => 'function(doc) {
              if(doc["couchrest-type"] && (doc["created_at"] || doc["updated_at"])) {
                var date = doc["updated_at"];
                
                if(date == null)
                  date = doc["created_at"];

                emit(doc._id, doc);
              }
            }'
          }

          couchrests_by_timestamp = {
            :map => 'function(doc) {
              if(doc["couchrest-type"] && (doc["created_at"] || doc["updated_at"])) {
                var date = doc["updated_at"];
                
                if(date == null)
                  date = doc["created_at"];

                emit(Date.parse(date), doc);
              }
            }'
          }

          database.save_doc({
            "_id" => "_design/CouchSphinxIndex",
            :lib_version => CouchSphinx::VERSION,
            :views => {
              :all_couchrests => all_couchrests,
              :couchrests_by_timestamp => couchrests_by_timestamp
            }
          })
        end
      end
    end
  end
end

# Include the Indexer mixin from the original ExtendedDocument class of
# CouchRest which adds a few methods and allows calling method indexed_with.

module CouchRest # :nodoc:
  class ExtendedDocument # :nodoc:
    include CouchRest::Mixins::Indexer
  end
end
