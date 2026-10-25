# frozen_string_literal: true

require 'securerandom'

module K9o
  # Minimal multipart/form-data encoder (stdlib only). Parts are hashes:
  #   { name: 'path', value: 'a.txt' }                       # plain field
  #   { name: 'file', value: bytes, filename: 'a.txt',        # file part
  #     content_type: 'text/plain' }
  # Values are sent as given, byte for byte (a String is its own bytes).
  module Multipart
    module_function

    # Returns [body (binary String), content_type header value].
    def encode(parts)
      payload = parts.map { |p| p[:value].to_s.b }
      boundary = nil
      loop do
        boundary = "----k9o-#{SecureRandom.hex(16)}"
        break unless payload.any? { |v| v.include?(boundary) }
      end

      body = String.new(encoding: Encoding::BINARY)
      parts.each_with_index do |p, i|
        disposition = %(form-data; name="#{escape(p[:name])}")
        disposition += %(; filename="#{escape(p[:filename])}") if p[:filename]
        body << "--#{boundary}\r\n".b
        body << "Content-Disposition: #{disposition}\r\n".b
        body << "Content-Type: #{p[:content_type]}\r\n".b if p[:content_type]
        body << "\r\n".b
        body << payload[i]
        body << "\r\n".b
      end
      body << "--#{boundary}--\r\n".b
      [body, "multipart/form-data; boundary=#{boundary}"]
    end

    def escape(value)
      value.to_s.gsub('"', '%22').gsub("\r", '%0D').gsub("\n", '%0A')
    end
  end
end
