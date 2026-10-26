# frozen_string_literal: true

require 'json'

module K9o
  # Data-plane DSL.
  #
  # Usage:
  #
  #   response = k9o.from('posts').select.eq('status', 'published').limit(10).execute
  #   response.data.each { |row| puts row }
  class FromBuilder
    def initialize(config, collection)
      @config = config
      @collection = collection
    end

    def select
      SelectBuilder.new(@config, @collection)
    end

    def insert(record)
      HttpTransport.request(
        config: @config, method: 'POST', path: FromBuilder.collection_path(@config, @collection), body: record
      )
    end

    def update(patch)
      UpdateBuilder.new(@config, @collection, patch)
    end

    def delete
      DeleteBuilder.new(@config, @collection)
    end

    def self.collection_path(config, collection)
      raise KError.new(
        code: 'K9O_MISSING_PROJECT_CONTEXT',
        message: 'data-plane operations require project_slug to be bound on the client',
        context: { collection: collection },
        recommendation: 'Pass project_slug: in K9o.create_client(...).'
      ) if config.project_slug.nil? || config.project_slug.empty?

      unless collection.is_a?(String) && collection.match?(/\A[a-z][a-z0-9_-]{0,62}\z/)
        raise KError.new(
          code: 'K9O_INVALID_FIELD_VALUE',
          message: "collection name #{collection.inspect} does not match required format",
          context: { collection: collection }
        )
      end
      UrlGrammar.project_path(config.project_slug, "data/#{collection}")
    end
  end

  # Shared filter/pagination state.
  class BaseBuilder
    def initialize(config, collection)
      @config = config
      @collection = collection
      @filters = []
      @limit_val = nil
      @cursor_val = nil
      @count_mode = nil
    end

    %i[eq neq gt gte lt lte like ilike is].each do |op|
      define_method(op) do |column, value|
        @filters << [column, op.to_s, value.to_s]
        self
      end
    end

    def in_(column, values)
      @filters << [column, 'in', "(#{values.map(&:to_s).join(',')})"]
      self
    end

    def not_in(column, values)
      @filters << [column, 'notIn', "(#{values.map(&:to_s).join(',')})"]
      self
    end

    def filter(column, op, value)
      @filters << [column, op.to_s, value.to_s]
      self
    end

    def limit(n)
      @limit_val = n
      self
    end

    def cursor(opaque)
      @cursor_val = opaque
      self
    end

    def count(mode)
      @count_mode = mode
      self
    end

    protected

    def to_query
      q = {}
      @filters.each do |col, op, val|
        q[col] = val.start_with?('(') ? "#{op}.#{val}" : "#{op}.#{val}"
      end
      q['limit'] = @limit_val.to_s if @limit_val
      q['cursor'] = @cursor_val if @cursor_val
      q['count'] = @count_mode if @count_mode
      q
    end
  end

  class SelectBuilder < BaseBuilder
    SEARCH_COLUMN = /\A[a-zA-Z_][a-zA-Z0-9_]{0,62}\z/.freeze
    SEARCH_LANGUAGE = /\A[a-zA-Z_]+\z/.freeze
    TEXT_TYPES = %w[plain phrase websearch].freeze
    VECTOR_METRICS = %w[cosine euclidean dot].freeze

    def initialize(config, collection)
      super
      @search = {}
    end

    # Full-text search over one text column. +type+ is "plain", "phrase" or "websearch".
    def text_search(column, query, language: 'english', type: 'plain')
      check_search_column(column)
      raise search_error('text search query must be a non-empty string') unless query.is_a?(String) && !query.empty?
      unless language.is_a?(String) && language.match?(SEARCH_LANGUAGE)
        raise search_error('text search language must be letters and underscores only')
      end

      type = type.to_s
      raise search_error("text search type must be one of #{TEXT_TYPES.join(', ')}") unless TEXT_TYPES.include?(type)

      @search.delete('textSearchLanguage')
      @search.delete('textSearchType')
      @search['textSearch'] = "#{column}:#{query}"
      @search['textSearchLanguage'] = language unless language == 'english'
      @search['textSearchType'] = type unless type == 'plain'
      self
    end

    # Nearest-neighbour search over one vector column; results come back closest first.
    # +metric+ is "cosine", "euclidean" or "dot"; +limit+ is 1 to 1000 (server default 10).
    def vector_search(column, embedding, metric: 'cosine', limit: nil)
      check_search_column(column)
      unless embedding.is_a?(Array) && !embedding.empty? &&
             embedding.all? { |v| v.is_a?(Integer) || (v.is_a?(Float) && v.finite?) }
        raise search_error('embedding must be a non-empty array of finite numbers')
      end

      metric = metric.to_s
      raise search_error("vector metric must be one of #{VECTOR_METRICS.join(', ')}") unless VECTOR_METRICS.include?(metric)
      unless limit.nil? || (limit.is_a?(Integer) && limit >= 1 && limit <= 1000)
        raise search_error('vector limit must be an integer from 1 to 1000')
      end

      @search.delete('vectorMetric')
      @search.delete('vectorLimit')
      @search['vectorSearch'] = "#{column}:#{JSON.generate(embedding)}"
      @search['vectorMetric'] = metric unless metric == 'cosine'
      @search['vectorLimit'] = limit.to_s unless limit.nil?
      self
    end

    def execute
      HttpTransport.request(
        config: @config, method: 'GET',
        path: FromBuilder.collection_path(@config, @collection),
        query: to_query.merge(@search)
      )
    end

    private

    def search_error(message)
      KError.new(code: 'K9O_INVALID_FIELD_VALUE', message: message, context: { collection: @collection })
    end

    def check_search_column(column)
      return if column.is_a?(String) && column.match?(SEARCH_COLUMN)

      raise search_error('search column must be a column name: letters, digits and underscores, starting with a letter or underscore')
    end
  end

  class UpdateBuilder < BaseBuilder
    def initialize(config, collection, patch)
      super(config, collection)
      @patch = patch
    end

    def execute
      id_filter = @filters.find { |col, op, _| col == 'id' && op == 'eq' }
      raise KError.new(
        code: 'K9O_INVALID_FIELD_VALUE',
        message: 'update() requires .eq("id", ...) filter; changing many rows in one call is not supported',
        context: { collection: @collection }
      ) unless id_filter

      path = "#{FromBuilder.collection_path(@config, @collection)}/#{id_filter[2]}"
      HttpTransport.request(config: @config, method: 'PATCH', path: path, body: @patch)
    end
  end

  class DeleteBuilder < BaseBuilder
    def execute
      id_filter = @filters.find { |col, op, _| col == 'id' && op == 'eq' }
      raise KError.new(
        code: 'K9O_INVALID_FIELD_VALUE',
        message: 'delete() requires .eq("id", ...) filter; deleting many rows in one call is not supported',
        context: { collection: @collection }
      ) unless id_filter

      path = "#{FromBuilder.collection_path(@config, @collection)}/#{id_filter[2]}"
      HttpTransport.request(config: @config, method: 'DELETE', path: path)
    end
  end
end
