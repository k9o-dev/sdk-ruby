# frozen_string_literal: true

module K9o
  # Studio namespace (workflows + dashboards).
  # Ruby idiom: snake_case + raise K9o::KError + Envelope return.
  #
  #   k9o.studio.workflows.list(status: 'active')
  #   k9o.studio.dashboards.pin('dsh_x')
  class Studio
    attr_reader :workflows, :dashboards

    def initialize(config)
      @workflows = Workflows.new(config)
      @dashboards = Dashboards.new(config)
    end

    def self.require_project_slug(config, surface)
      slug = config.project_slug
      if slug.nil? || slug.empty?
        raise KError.new(
          code: 'K9O_MISSING_PROJECT_CONTEXT',
          message: "#{surface} operations require project_slug bound on the client"
        )
      end
      slug
    end

    # k9o.studio.workflows.*
    class Workflows
      attr_reader :runs

      def initialize(config)
        @config = config
        @runs = Runs.new(config)
      end

      # GET /@<slug>/workflows — the route filters by +status+ and pages with +limit+ / +cursor+.
      def list(status: nil, limit: nil, cursor: nil)
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        q = {}
        q['status'] = status if status
        q['limit'] = limit if limit
        q['cursor'] = cursor if cursor
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, 'workflows'), query: q)
      end

      # POST /@<slug>/workflows. +workflow+ is the gateway's body: 'name', 'triggerType', 'triggerConfig',
      # 'actions' (each { 'index', 'action_type', 'config', ... }), optional 'description', 'status', 'rbacBinding'.
      def create(workflow)
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, 'workflows'), body: workflow)
      end

      def read(workflow_id)
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, "workflows/#{encode(workflow_id)}"))
      end

      def update(workflow_id, updates)
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        HttpTransport.request(config: @config, method: 'PATCH',
                              path: UrlGrammar.project_path(slug, "workflows/#{encode(workflow_id)}"), body: updates)
      end

      def delete(workflow_id)
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        HttpTransport.request(config: @config, method: 'DELETE',
                              path: UrlGrammar.project_path(slug, "workflows/#{encode(workflow_id)}"))
      end

      # Manual-trigger a run (manual workflows only): POST /@<slug>/workflows/<id>/runs { triggerContext }.
      def trigger(workflow_id, trigger_context = {})
        slug = Studio.require_project_slug(@config, 'studio.workflows')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, "workflows/#{encode(workflow_id)}/runs"),
                              body: { 'triggerContext' => trigger_context })
      end

      private

      def encode(s)
        ::URI.encode_www_form_component(s)
      end

      # k9o.studio.workflows.runs.*
      class Runs
        def initialize(config)
          @config = config
        end

        # GET /@<slug>/workflows/<id>/runs — pages with +limit+ / +cursor+ (the route has no status filter).
        def list(workflow_id, limit: nil, cursor: nil)
          slug = Studio.require_project_slug(@config, 'studio.workflows')
          q = {}
          q['limit'] = limit if limit
          q['cursor'] = cursor if cursor
          HttpTransport.request(config: @config, method: 'GET',
                                path: UrlGrammar.project_path(slug, "workflows/#{enc(workflow_id)}/runs"), query: q)
        end

        def read(workflow_id, run_id)
          slug = Studio.require_project_slug(@config, 'studio.workflows')
          HttpTransport.request(config: @config, method: 'GET',
                                path: UrlGrammar.project_path(slug, "workflows/#{enc(workflow_id)}/runs/#{enc(run_id)}"))
        end

        def cancel(workflow_id, run_id)
          slug = Studio.require_project_slug(@config, 'studio.workflows')
          HttpTransport.request(config: @config, method: 'POST',
                                path: UrlGrammar.project_path(slug, "workflows/#{enc(workflow_id)}/runs/#{enc(run_id)}/cancel"))
        end

        private

        def enc(s)
          ::URI.encode_www_form_component(s)
        end
      end
    end

    # k9o.studio.dashboards.* — widget fields on the wire are snake_case ('widget_type', 'data_source', 'config').
    class Dashboards
      def initialize(config)
        @config = config
      end

      # GET /@<slug>/dashboards — filters: +status+, +pinned_only+; pages with +limit+ / +cursor+.
      def list(status: nil, pinned_only: nil, limit: nil, cursor: nil)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        q = {}
        q['status'] = status if status
        q['pinnedOnly'] = pinned_only.to_s unless pinned_only.nil?
        q['limit'] = limit if limit
        q['cursor'] = cursor if cursor
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, 'dashboards'), query: q)
      end

      def create(dashboard)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, 'dashboards'), body: dashboard)
      end

      def read(dashboard_id)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'GET',
                              path: UrlGrammar.project_path(slug, "dashboards/#{enc(dashboard_id)}"))
      end

      def update(dashboard_id, updates)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'PATCH',
                              path: UrlGrammar.project_path(slug, "dashboards/#{enc(dashboard_id)}"), body: updates)
      end

      def delete(dashboard_id)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'DELETE',
                              path: UrlGrammar.project_path(slug, "dashboards/#{enc(dashboard_id)}"))
      end

      def pin(dashboard_id)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, "dashboards/#{enc(dashboard_id)}/pin"))
      end

      def unpin(dashboard_id)
        slug = Studio.require_project_slug(@config, 'studio.dashboards')
        HttpTransport.request(config: @config, method: 'POST',
                              path: UrlGrammar.project_path(slug, "dashboards/#{enc(dashboard_id)}/unpin"))
      end

      private

      def enc(s)
        ::URI.encode_www_form_component(s)
      end
    end
  end
end
