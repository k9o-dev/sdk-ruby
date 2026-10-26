# frozen_string_literal: true

require 'cgi'

module K9o
  # `client.storage` buckets and objects, against
  # `/@<project_slug>/storage/buckets...`.
  #
  #   k9o.storage.create_bucket('avatars', public: false)
  #   k9o.storage.from('avatars').upload('user/a.jpg', bytes, content_type: 'image/jpeg')
  #   k9o.storage.from('avatars').create_signed_url('user/a.jpg', expires_in: 300)
  #
  # Bucket names are logical (the platform resolves the physical store).
  # Signed URLs require an explicit `expires_in` (1..604800, no default).
  # Not offered, by design: signed PUT upload URLs (no gateway route) and copy.
  # Errors pass through unchanged as K9o::KError; object bytes never appear in
  # an SDK-constructed error.
  class Storage
    MAX_EXPIRES_IN = 604_800

    def initialize(config)
      @config = config
    end

    # GET /@<slug>/storage/buckets
    def list_buckets
      HttpTransport.request(config: @config, method: 'GET', path: buckets_path)
    end

    # GET .../buckets/<name>
    def get_bucket(name)
      HttpTransport.request(config: @config, method: 'GET', path: bucket_path(name))
    end

    # POST .../buckets  body { name, ...options }. Options are sent as given:
    # public, fileSizeLimit, allowedMimeTypes, versioning, deleteAfterDays,
    # byosBindingId (snake_case keys are mapped to the wire's camelCase).
    def create_bucket(name, public: nil, file_size_limit: nil, allowed_mime_types: nil, versioning: nil,
                      delete_after_days: nil, byos_binding_id: nil)
      body = { 'name' => name }
      body['public'] = public unless public.nil?
      body['fileSizeLimit'] = file_size_limit unless file_size_limit.nil?
      body['allowedMimeTypes'] = allowed_mime_types unless allowed_mime_types.nil?
      body['versioning'] = versioning unless versioning.nil?
      body['deleteAfterDays'] = delete_after_days unless delete_after_days.nil?
      body['byosBindingId'] = byos_binding_id unless byos_binding_id.nil?
      HttpTransport.request(config: @config, method: 'POST', path: buckets_path, body: body)
    end

    # PATCH .../buckets/<name>. `patch` is a Hash of only the fields to change
    # (snake_case or wire camelCase keys); an explicit nil clears a limit
    # (fileSizeLimit, allowedMimeTypes, deleteAfterDays, byosBindingId).
    def update_bucket(name, patch)
      body = patch.each_with_object({}) { |(k, v), h| h[wire_key(k)] = v }
      HttpTransport.request(config: @config, method: 'PATCH', path: bucket_path(name), body: body)
    end

    # DELETE .../buckets/<name>; `?empty=true` only when empty is true
    # (purges the bucket's objects first).
    def delete_bucket(name, empty: false)
      query = empty == true ? { 'empty' => 'true' } : nil
      HttpTransport.request(config: @config, method: 'DELETE', path: bucket_path(name), query: query)
    end

    # A handle on one bucket for object operations.
    def from(bucket)
      BucketHandle.new(@config, bucket)
    end

    WIRE_KEYS = {
      'file_size_limit' => 'fileSizeLimit', 'allowed_mime_types' => 'allowedMimeTypes',
      'delete_after_days' => 'deleteAfterDays', 'byos_binding_id' => 'byosBindingId'
    }.freeze

    def self.buckets_path(config, suffix = '')
      slug = Studio.require_project_slug(config, 'storage')
      UrlGrammar.project_path(slug, "storage/buckets#{suffix}")
    end

    def self.bucket_path(config, name, suffix = '')
      invalid('bucket name must not be empty', 'bucket') unless name.is_a?(String) && !name.empty?
      # `.` and `..` survive percent-encoding and are collapsed as dot segments
      # by URL layers, so they would address a different route.
      invalid('bucket name must not be a dot segment', 'bucket', 'dot_segment') if name == '.' || name == '..'
      buckets_path(config, "/#{CGI.escape(name).gsub('+', '%20')}#{suffix}")
    end

    def self.invalid(message, field, reason = 'empty')
      raise KError.new(code: 'K9O_INVALID_FIELD_VALUE', message: message,
                       context: { field: field, reason: reason })
    end

    private

    def wire_key(key)
      k = key.to_s
      WIRE_KEYS.fetch(k, k)
    end

    def buckets_path
      Storage.buckets_path(@config)
    end

    def bucket_path(name)
      Storage.bucket_path(@config, name)
    end

    # Object operations on one bucket: k9o.storage.from('avatars').
    class BucketHandle
      def initialize(config, bucket)
        @config = config
        @bucket = bucket
      end

      # POST .../objects (multipart/form-data: file, path, contentType?, upsert, metadata?).
      # `data` is a String (sent as its bytes), or an IO-like responding to #read.
      # `upsert: false` (default) refuses to overwrite an existing path (409).
      def upload(path, data, content_type: nil, upsert: false, metadata: nil)
        require_object_path(path)
        bytes = data.respond_to?(:read) ? data.read : data
        unless bytes.is_a?(String)
          Storage.invalid('upload data must be a String or an IO', 'data', 'type')
        end
        bytes = bytes.encode(Encoding::UTF_8) unless [Encoding::BINARY, Encoding::UTF_8].include?(bytes.encoding)
        file = { name: 'file', value: bytes, filename: path.split('/').last.to_s.then { |f| f.empty? ? 'file' : f } }
        file[:content_type] = content_type || 'application/octet-stream'
        parts = [file, { name: 'path', value: path }]
        parts << { name: 'contentType', value: content_type } unless content_type.nil?
        parts << { name: 'upsert', value: upsert == true ? 'true' : 'false' }
        parts << { name: 'metadata', value: JSON.dump(metadata) } unless metadata.nil?
        HttpTransport.request(config: @config, method: 'POST', path: objects_path, multipart: parts)
      end

      # POST .../objects/sign { path, expiresIn, download? }. `expires_in` is
      # required: an Integer from 1 to 604800 seconds; refused before any request.
      def create_signed_url(path, expires_in:, download: nil)
        require_object_path(path)
        unless expires_in.is_a?(Integer) && expires_in >= 1 && expires_in <= MAX_EXPIRES_IN
          raise KError.new(
            code: 'K9O_INVALID_FIELD_VALUE',
            message: "expires_in is required and must be an integer from 1 to #{MAX_EXPIRES_IN} seconds",
            context: { field: 'expiresIn', reason: 'out_of_range' },
            recommendation: 'Pass an explicit expires_in; signed URLs have no default lifetime.'
          )
        end
        body = { 'path' => path, 'expiresIn' => expires_in }
        body['download'] = download unless download.nil?
        HttpTransport.request(config: @config, method: 'POST', path: objects_path('/sign'), body: body)
      end

      # GET .../objects, with ?prefix= only when given.
      def list(prefix: nil)
        query = prefix.nil? ? nil : { 'prefix' => prefix }
        HttpTransport.request(config: @config, method: 'GET', path: objects_path, query: query)
      end

      # DELETE .../objects?path=
      def remove(path)
        require_object_path(path)
        HttpTransport.request(config: @config, method: 'DELETE', path: objects_path, query: { 'path' => path })
      end

      private

      def objects_path(suffix = '')
        Storage.bucket_path(@config, @bucket, "/objects#{suffix}")
      end

      def require_object_path(path)
        return if path.is_a?(String) && !path.empty?

        Storage.invalid('object path must not be empty', 'path')
      end
    end
  end
end
