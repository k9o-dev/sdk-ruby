# frozen_string_literal: true

module K9o
  # `client.query(sql, params)` and `client.search(collection, column:, q:)`.
  #
  # Wire (project-plane):
  #   POST /@<slug>/query   body { sql:, params? }   -> { data: [row, ...], meta }
  #   GET  /@<slug>/data/<collection>?textSearch=<column>:<q>...   (the select builder's +text_search+)
  #
  # +params+ is an Array (positional, bound to $1, $2, ...; the SQL is sent as written) or a Hash of named values
  # (+:name+ placeholders are rewritten to $n here and the values become the positional list). Values are bound by
  # the database, never interpolated into the SQL text.
  module Query
    IDENT_START = /[A-Za-z_]/.freeze
    IDENT_CHAR = /[A-Za-z0-9_]/.freeze
    DOLLAR_TAG = /\A\$([A-Za-z_][A-Za-z0-9_]*)?\$/.freeze

    module_function

    def invalid(message, context = {})
      KError.new(code: 'K9O_INVALID_FIELD_VALUE', message: message, context: context)
    end

    def check_value(value, where)
      return value if value.nil? || value == true || value == false || value.is_a?(String)
      return value if value.is_a?(Integer)
      return value if value.is_a?(Float) && value.finite?

      raise invalid("#{where} must be a string, number, boolean or nil; serialise anything else (for example as JSON text) first")
    end

    def lookup(named, name)
      return [true, named[name]] if named.key?(name)
      return [true, named[name.to_sym]] if named.key?(name.to_sym)

      [false, nil]
    end

    # Rewrite +:name+ placeholders to $n. Skips quoted text, comments, dollar-quoted strings and +::+ casts.
    # Returns [sql, params].
    def translate_named_params(sql, named)
      order = []
      out = +''
      i = 0
      n = sql.length
      while i < n
        c = sql[i]
        nxt = i + 1 < n ? sql[i + 1] : ''
        if c == "'" || ((c == 'E' || c == 'e') && nxt == "'" && !(i > 0 && sql[i - 1] =~ IDENT_CHAR))
          escapes = c != "'"
          j = escapes ? i + 2 : i + 1
          while j < n
            if escapes && sql[j] == '\\'
              j += 2
              next
            end
            if sql[j] == "'"
              if sql[j + 1] == "'"
                j += 2
                next
              end
              break
            end
            j += 1
          end
          out << sql[i...[j + 1, n].min]
          i = j + 1
        elsif c == '"'
          j = i + 1
          while j < n
            if sql[j] == '"'
              if sql[j + 1] == '"'
                j += 2
                next
              end
              break
            end
            j += 1
          end
          out << sql[i...[j + 1, n].min]
          i = j + 1
        elsif c == '-' && nxt == '-'
          j = sql.index("\n", i) || n
          out << sql[i...j]
          i = j
        elsif c == '/' && nxt == '*'
          depth = 1
          j = i + 2
          while j < n && depth > 0
            if sql[j, 2] == '/*'
              depth += 1
              j += 2
            elsif sql[j, 2] == '*/'
              depth -= 1
              j += 2
            else
              j += 1
            end
          end
          out << sql[i...j]
          i = j
        elsif c == '$'
          m = DOLLAR_TAG.match(sql[i..-1])
          if m
            close = sql.index(m[0], i + m[0].length)
            stop = close.nil? ? n : close + m[0].length
            out << sql[i...stop]
            i = stop
          else
            out << c
            i += 1
          end
        elsif c == ':' && nxt == ':'
          out << '::'
          i += 2
        elsif c == ':' && nxt != '' && nxt =~ IDENT_START && !(i > 0 && sql[i - 1] =~ IDENT_CHAR)
          j = i + 2
          j += 1 while j < n && sql[j] =~ IDENT_CHAR
          name = sql[(i + 1)...j]
          unless order.include?(name)
            found, = lookup(named, name)
            raise invalid("no value for :#{name}", name: name) unless found

            order << name
          end
          out << "$#{order.index(name) + 1}"
          i = j
        else
          out << c
          i += 1
        end
      end
      values = order.map { |name| check_value(lookup(named, name)[1], "the value for :#{name}") }
      [out, values]
    end

    # Builds [path, body] for POST /@<slug>/query.
    def prepare(config, sql, params)
      slug = Studio.require_project_slug(config, 'query')
      text = sql
      values = []
      if params.is_a?(Hash)
        text, values = translate_named_params(sql, params)
      elsif !params.nil?
        values = params.each_with_index.map { |v, i| check_value(v, "params[#{i}]") }
      end
      body = { 'sql' => text }
      body['params'] = values unless values.empty?
      [UrlGrammar.project_path(slug, 'query'), body]
    end
  end

  # Client-root methods mixed into K9oClient.
  module QueryMethods
    # POST /@<slug>/query — run one read-only SQL statement; +data+ is the array of rows.
    # An Array binds positionally to $1, $2, ...; a Hash binds +:name+ placeholders.
    def query(sql, params = nil)
      path, body = Query.prepare(@config, sql, params)
      HttpTransport.request(config: @config, method: 'POST', path: path, body: body)
    end

    # Full-text search over one text column of a collection, best matches first. Sugar over
    # +from(collection).select.text_search(column, q, ...)+; +limit+ and +cursor+ page the result.
    def search(collection, column:, q:, language: nil, type: nil, limit: nil, cursor: nil)
      opts = {}
      opts[:language] = language unless language.nil?
      opts[:type] = type unless type.nil?
      builder = from(collection).select.text_search(column, q, **opts)
      builder.limit(limit) unless limit.nil?
      builder.cursor(cursor) unless cursor.nil?
      builder.execute
    end
  end
end
