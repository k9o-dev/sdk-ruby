# frozen_string_literal: true

module K9o
  # Schema: k9o.schema.*
  #
  #   collections.list(limit:, cursor:)    GET /@<slug>/schema/collections
  #
  # The list is cursor-paginated and ordered by collection name: pass +meta.cursor.next+ of one page as +cursor+ of
  # the next, until it is nil.
  class Schema
    attr_reader :collections

    def initialize(config)
      @collections = SchemaCollections.new(config)
    end
  end

  class SchemaCollections
    def initialize(config)
      @config = config
    end

    # The project's collections by name, one page at a time. +limit+ is 1 to 200 (default 50).
    def list(limit: nil, cursor: nil)
      route = UrlGrammar.project_path(Studio.require_project_slug(@config, 'schema'), 'schema/collections')
      ApprovalChecks.check_limit(limit)
      raise ApprovalChecks.invalid('cursor must be a string', cursor: cursor) unless cursor.nil? || cursor.is_a?(String)

      query = {}
      query['limit'] = limit unless limit.nil?
      query['cursor'] = cursor unless cursor.nil?
      HttpTransport.request(config: @config, method: 'GET', path: route, query: query)
    end
  end
end
