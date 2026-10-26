# frozen_string_literal: true

module K9o
  # Shared argument checks for the approvals, approval policy and schema namespaces. A bad value raises
  # K9o::KError K9O_INVALID_FIELD_VALUE before any request is sent.
  module ApprovalChecks
    module_function

    def invalid(message, context = {})
      KError.new(code: 'K9O_INVALID_FIELD_VALUE', message: message, context: context)
    end

    def check_limit(limit)
      return if limit.nil?
      return if limit.is_a?(Integer) && limit >= 1 && limit <= 200

      raise invalid('limit must be a whole number from 1 to 200', limit: limit)
    end

    def id_segment(value, what)
      raise invalid("#{what} id must be a non-empty string") unless value.is_a?(String) && !value.empty?

      ::URI.encode_www_form_component(value).gsub('+', '%20')
    end

    def reason!(reason)
      raise invalid('reason is required and must be a non-empty string') unless reason.is_a?(String) && !reason.strip.empty?

      reason
    end

    def predicate!(value, field)
      raise invalid("#{field} must be a predicate object") unless value.is_a?(Hash)

      value
    end

    def enum!(value, allowed, field)
      text = value.is_a?(Symbol) ? value.to_s : value
      return text if allowed.include?(text)

      raise invalid("#{field} must be #{allowed.map { |a| "\"#{a}\"" }.join(', ')}", field.to_sym => value)
    end
  end

  # Pending-change queue: k9o.approvals.*
  #
  #   list(status:, limit:)                GET  /@<slug>/pending-approvals
  #   get(id)                              GET  /@<slug>/pending-approvals/<id>
  #   approve(id, reason:)                 POST /@<slug>/pending-approvals/<id>/approve
  #   reject(id, reason:)                  POST /@<slug>/pending-approvals/<id>/reject
  #   bulk(action:, criteria:, reason:)    POST /@<slug>/pending-approvals/bulk
  #
  # +list+ is not paginated: it returns the newest +limit+ changes (1 to 200, default 50). +approve+ can answer 200
  # with +status+ still +pending_approval+: the approval is recorded and more approvers are needed. +bulk+ skips rows
  # that fail without a report, so compare +affectedIds+ with what you intended.
  class Approvals
    def initialize(config)
      @config = config
    end

    # Pending changes, newest first. Only +limit+ caps the result.
    def list(status: nil, limit: nil)
      ApprovalChecks.check_limit(limit)
      query = {}
      query['status'] = status.to_s unless status.nil?
      query['limit'] = limit unless limit.nil?
      call('GET', path, query: query)
    end

    # One pending change. Members who are not queue admins can read only their own.
    def get(id)
      call('GET', path("/#{ApprovalChecks.id_segment(id, 'approval')}"))
    end

    # Approve a pending change. Read +status+ on the answer: +pending_approval+ means more approvers are needed.
    def approve(id, reason: nil)
      seg = ApprovalChecks.id_segment(id, 'approval')
      call('POST', path("/#{seg}/approve"), body: reason.nil? ? {} : { 'reason' => reason })
    end

    # Reject a pending change. +reason+ is required and must not be empty.
    def reject(id, reason:)
      seg = ApprovalChecks.id_segment(id, 'approval')
      call('POST', path("/#{seg}/reject"), body: { 'reason' => ApprovalChecks.reason!(reason) })
    end

    # Approve or reject every pending change matching +criteria+ (a predicate Hash). +reason+ is required to reject.
    # Rows that fail are skipped without a report: compare +affectedIds+ with what you intended.
    def bulk(action:, criteria:, reason: nil)
      act = ApprovalChecks.enum!(action, %w[approve reject], 'action')
      body = { 'action' => act, 'criteria' => ApprovalChecks.predicate!(criteria, 'criteria') }
      if act == 'reject'
        body['reason'] = ApprovalChecks.reason!(reason)
      elsif !reason.nil?
        body['reason'] = reason
      end
      call('POST', path('/bulk'), body: body)
    end

    private

    def call(method, route, body: nil, query: nil)
      HttpTransport.request(config: @config, method: method, path: route, body: body, query: query)
    end

    def path(tail = '')
      UrlGrammar.project_path(Studio.require_project_slug(@config, 'approvals'), "pending-approvals#{tail}")
    end
  end

  # Approval policies: k9o.approval_policies.*
  #
  #   list                                              GET    /@<slug>/approval-policies
  #   create(collection:, operation:, action:, predicate:)  POST   /@<slug>/approval-policies
  #   delete(id)                                        DELETE /@<slug>/approval-policies/<id>
  class ApprovalPolicies
    COLLECTION_RE = /\A[a-zA-Z_][a-zA-Z0-9_]{0,62}\z/.freeze

    def initialize(config)
      @config = config
    end

    # All policies, oldest first. The first matching policy for a write decides.
    def list
      call('GET', path)
    end

    # Create a policy. Identical policies are not de-duplicated.
    def create(collection:, operation:, action:, predicate:)
      unless collection.is_a?(String) && COLLECTION_RE.match?(collection)
        raise ApprovalChecks.invalid('collection must match ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$', collection: collection)
      end

      body = {
        'collection' => collection,
        'operation' => ApprovalChecks.enum!(operation, %w[insert update delete], 'operation'),
        'action' => ApprovalChecks.enum!(action, %w[auto_approve queue], 'action'),
        'predicate' => ApprovalChecks.predicate!(predicate, 'predicate')
      }
      call('POST', path, body: body)
    end

    # Delete a policy; the answer is { 'id' => ... }.
    def delete(id)
      call('DELETE', path("/#{ApprovalChecks.id_segment(id, 'policy')}"))
    end

    private

    def call(method, route, body: nil)
      HttpTransport.request(config: @config, method: method, path: route, body: body)
    end

    def path(tail = '')
      UrlGrammar.project_path(Studio.require_project_slug(@config, 'approval_policies'), "approval-policies#{tail}")
    end
  end
end
