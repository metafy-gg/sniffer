# frozen_string_literal: true

require "benchmark"

module Sniffer
  module Adapters
    # HTTP adapter
    module HTTPAdapter
      # private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def request_with_sniffer(verb, uri,
        headers: nil, params: nil, form: nil, json: nil, body: nil,
        response: nil, encoding: nil, follow: nil, ssl: nil, ssl_context: nil,
        proxy: nil, nodelay: nil, features: nil, retriable: nil,
        socket_class: nil, ssl_socket_class: nil, timeout_class: nil,
        timeout_options: nil, keep_alive_timeout: nil, base_uri: nil, persistent: nil)
        opts = {
          headers: headers,
          params: params,
          form: form,
          json: json,
          body: body,
          response: response,
          encoding: encoding,
          follow: follow,
          ssl: ssl,
          ssl_context: ssl_context,
          proxy: proxy,
          nodelay: nodelay,
          features: features,
          retriable: retriable,
          socket_class: socket_class,
          ssl_socket_class: ssl_socket_class,
          timeout_class: timeout_class,
          timeout_options: timeout_options,
          keep_alive_timeout: keep_alive_timeout,
          base_uri: base_uri,
          persistent: persistent
        }.compact

        opts = @default_options.merge(opts)
        builder = HTTP::Request::Builder.new(opts)
        req = builder.build(verb, uri)
        data_item = build_data_item(req)
        Sniffer.store(data_item) if data_item

        bm = Benchmark.realtime do
          @res = perform(req, opts)
        end

        if data_item
          data_item.response = Sniffer::DataItem::Response.new(status: @res.code,
            headers: @res.headers.to_h,
            body: @res.body,
            timing: bm)

          Sniffer.notify_response(data_item)
        end

        return @res unless opts.follow

        HTTP::Redirector.new(**opts.follow).perform(req, @res) do |request|
          perform(builder.wrap(request), opts)
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      def build_data_item(req)
        return unless Sniffer.enabled?

        query = req.uri.path
        query += "?#{req.uri.query}" if req.uri.query

        data_item = Sniffer::DataItem.new
        data_item.request = Sniffer::DataItem::Request.new(host: req.uri.host,
          method: req.verb,
          query: query,
          headers: req.headers.to_h,
          body: req.body.source,
          port: req.uri.port)
        data_item
      end

      # Only used when prepending, see all_prepend.rb
      module Prepend
        include HTTPAdapter

        def request(*args, **kwargs)
          request_with_sniffer(*args, **kwargs)
        end
      end
    end
  end
end

if defined?(::HTTP::Client)
  if defined?(Sniffer::Adapters::HTTPAdapter::PREPEND)
    HTTP::Client.prepend Sniffer::Adapters::HTTPAdapter::Prepend
  else
    HTTP::Client.class_eval do
      include Sniffer::Adapters::HTTPAdapter

      alias_method :request_without_sniffer, :request
      alias_method :request, :request_with_sniffer
    end
  end
end
