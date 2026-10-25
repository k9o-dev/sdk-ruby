# frozen_string_literal: true

module K9o
  # Migration lifecycle namespace — k9o.migrations.*.
  #
  # TYPE MODEL (, cemented f21b3c15 — Ruby is TIER-3):
  #
  #   Ruby keeps a RUNTIME HASH PASS-THROUGH for migration payloads (the
  #   gateway is the fail-closed source of truth; SDK types are ergonomics +
  #   serialization, never validation). The structured shape is documented
  #   below AND statically checkable via the shipped RBS signatures in
  #   sig/k9o/migrations.rbs (steep/typeprof), per the tier-3 contract:
  #   "documented + statically-checkable pass-through".
  #
  #   The control-plane request/submit shape (the +migrations+ array) is the
  #   FIXED migration Operation union — control-plane, so it is TYPED. Build
  #   well-formed operation hashes with the keyword-arg helpers on
  #   K9o::Migrations::Build (idiomatic Ruby "typed" constructors) which emit
  #   exactly the wire JSON; or hand-author the hash against the documented
  #   shape. The closed-union property (exactly these 7 ops) is enforced at
  #   wire + server validation for all tiers.
  #
  # WIRE SHAPE (snake_case keys, matches packages/core/src/migrations.ts):
  #
  #   migration = {
  #     'version' => Integer,           # NOTE: integer, not a "001" string
  #     'slug'    => String,
  #     'up'      => [Operation, ...],
  #     'down'    => [Operation, ...],
  #     'policy'  => MigrationPolicy,   # optional
  #   }
  #
  #   Operation — KEY-TAGGED union, EXACTLY ONE key, one of these 7 (alter_table
  #   is the batched column mutation, live in the gateway runner; rename_column
  #   remains a pending future op, intentionally absent):
  #     { 'create_table' => { 'name' => String,
  #                           'columns' => [ColumnSpec, ...],
  #                           'indexes' => [IndexSpec, ...] } }   # indexes optional
  #     { 'drop_table'   => String }
  #     { 'add_column'   => { 'table' => String, 'column' => ColumnSpec } }
  #     { 'drop_column'  => { 'table' => String, 'column' => String } }
  #     { 'create_index' => { 'table' => String, 'index' => IndexSpec } }
  #     { 'drop_index'   => { 'name'  => String } }
  #
  #   ColumnSpec = {
  #     'name'          => String,
  #     'type'          => String,      # parser-owned vocabulary; NOT an enum
  #     'primary_key'   => true|false,  # optional
  #     'not_null'      => true|false,  # optional
  #     'unique'        => true|false,  # optional
  #     'default'       => String,      # optional
  #     'references'    => ColumnReferences, # optional
  #     'encrypted'     => true | { 'store' => 'inline'|'vault',
  #                                 'searchable' => true|false },  # optional
  #                       # NOTE: 'searchable' is NESTED inside the object form,
  #                       # NOT a sibling of the column.
  #     'blind_indexed' => true|false,  # optional (C-mode equality lookup)
  #   }
  #
  #   IndexSpec        = { 'name' => String (optional), 'columns' => [String, ...],
  #                        'unique' => true|false (optional) }
  #   ColumnReferences = { 'collection' => String, 'on' => String,
  #                        'on_delete' => 'CASCADE'|'RESTRICT'|'SET NULL'|'NO ACTION' (opt),
  #                        'on_update' => same (opt) }
  #
  #   MigrationPolicy  = { 'collections' => { String => CollectionPolicy },
  #                        'storage' => { 'buckets' => { String => StorageBucketPolicy } } }
  #   CollectionPolicy = { 'references' => [RelationshipSpec, ...],
  #                        'actions' => { 'select'|'insert'|'update'|'delete' => ActionRule } }
  #   RelationshipSpec = { 'collection' => String, 'on' => String, 'as' => String,
  #                        'type' => 'inner'|'left' (opt) }
  #   ActionRule       = { 'rule' => any (opt) }
  #   StorageBucketPolicy = { 'public' => true|false (opt),
  #                           'actions' => { 'read'|'upload'|'delete'|'list' => ActionRule } }
  #
  # RESPONSE records (returned in the envelope data, pass-through hashes):
  #   AppliedMigration = { 'version' => Integer, 'slug' => String,
  #                        'checksum' => String, 'appliedAt' => String }
  #   PendingMigration = { 'pendingId' => String, 'version' => Integer,
  #                        'slug' => String, 'checksum' => String,
  #                        'submittedAt' => String, 'submittedBy' => String }
  class Migrations
    def initialize(config)
      @config = config
    end

    # Apply migrations immediately (PROJECT_ADMIN minimum).
    # +migrations+ is an array of migration hashes (see the shape above; build
    # operation hashes with K9o::Migrations::Build).
    def apply(migrations)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'migrations/apply'), body: { 'migrations' => migrations })
    end

    def list
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'migrations'))
    end

    def get(version)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET',
                            path: UrlGrammar.project_path(slug, "migrations/#{enc(version)}"))
    end

    # Queue migrations for maker-checker approval.
    def queue(migrations)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, 'migrations/queue'), body: { 'migrations' => migrations })
    end

    def list_pending
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'GET', path: UrlGrammar.project_path(slug, 'migrations/pending'))
    end

    def apply_pending(pending_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, "migrations/pending/#{enc(pending_id)}/apply"))
    end

    def reject_pending(pending_id, reason: nil)
      slug = require_project_slug
      body = reason ? { 'reason' => reason } : nil
      HttpTransport.request(config: @config, method: 'POST',
                            path: UrlGrammar.project_path(slug, "migrations/pending/#{enc(pending_id)}/reject"), body: body)
    end

    def delete_pending(pending_id)
      slug = require_project_slug
      HttpTransport.request(config: @config, method: 'DELETE',
                            path: UrlGrammar.project_path(slug, "migrations/pending/#{enc(pending_id)}"))
    end

    # Typed keyword-arg constructors for the FIXED control-plane migration
    # Operation union + its sub-shapes. Each returns the exact wire hash; nil
    # keyword args are omitted so the emitted JSON matches the canonical
    # `omitempty`/optional shape (packages/core/src/migrations.ts,
    # packages/go/migrations.go). These are the tier-3 "typed request object"
    # surface — the RBS in sig/k9o/migrations.rbs gives them static checking.
    module Build
      module_function

      # --- ColumnSpec --------------------------------------------------------
      # +encrypted+: pass `true` for the inline shorthand, or the object hash
      # `{ 'store' => 'inline'|'vault', 'searchable' => bool }`. Prefer the
      # column_encryption helper to build the object form correctly (searchable
      # NESTED, never a sibling).
      def column(name:, type:, primary_key: nil, not_null: nil, unique: nil,
                 default: nil, references: nil, encrypted: nil, blind_indexed: nil)
        h = { 'name' => name, 'type' => type }
        h['primary_key']   = primary_key   unless primary_key.nil?
        h['not_null']      = not_null       unless not_null.nil?
        h['unique']        = unique         unless unique.nil?
        h['default']       = default        unless default.nil?
        h['references']    = references     unless references.nil?
        h['encrypted']     = encrypted      unless encrypted.nil?
        h['blind_indexed'] = blind_indexed  unless blind_indexed.nil?
        h
      end

      # Object form of the `encrypted` union. The bare `true` shorthand needs no
      # helper — just pass `encrypted: true`. Here +searchable+ is NESTED inside
      # the returned object, per the cemented shape.
      def column_encryption(store:, searchable: nil)
        h = { 'store' => store }
        h['searchable'] = searchable unless searchable.nil?
        h
      end

      def references(collection:, on:, on_delete: nil, on_update: nil)
        h = { 'collection' => collection, 'on' => on }
        h['on_delete'] = on_delete unless on_delete.nil?
        h['on_update'] = on_update unless on_update.nil?
        h
      end

      def index(columns:, name: nil, unique: nil)
        h = { 'columns' => columns }
        h['name']   = name   unless name.nil?
        h['unique'] = unique unless unique.nil?
        h
      end

      # --- Operation union (exactly one key per op) --------------------------
      def create_table(name:, columns:, indexes: nil)
        op = { 'name' => name, 'columns' => columns }
        op['indexes'] = indexes unless indexes.nil?
        { 'create_table' => op }
      end

      def drop_table(name)
        { 'drop_table' => name }
      end

      def add_column(table:, column:)
        { 'add_column' => { 'table' => table, 'column' => column } }
      end

      def drop_column(table:, column:)
        { 'drop_column' => { 'table' => table, 'column' => column } }
      end

      # alter_table — BATCHED column mutation: one op carries optional
      # add_columns + drop_columns (not separate ops). add_columns entries are
      # full column_spec; drop_columns is column names. Live in the gateway
      # runner.
      def alter_table(name:, add_columns: nil, drop_columns: nil)
        op = { 'name' => name }
        op['add_columns'] = add_columns unless add_columns.nil?
        op['drop_columns'] = drop_columns unless drop_columns.nil?
        { 'alter_table' => op }
      end

      def create_index(table:, index:)
        { 'create_index' => { 'table' => table, 'index' => index } }
      end

      def drop_index(name:)
        { 'drop_index' => { 'name' => name } }
      end

      # --- Migration ---------------------------------------------------------
      def migration(version:, slug:, up:, down:, policy: nil)
        h = { 'version' => version, 'slug' => slug, 'up' => up, 'down' => down }
        h['policy'] = policy unless policy.nil?
        h
      end
    end

    private

    def require_project_slug
      Studio.require_project_slug(@config, 'migrations')
    end

    def enc(s)
      ::URI.encode_www_form_component(s)
    end
  end
end
