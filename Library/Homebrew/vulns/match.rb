# typed: strict
# frozen_string_literal: true

require "formula_versions"
require "vulns/cpan_sec"
require "vulns/identify"
require "vulns/osv"
require "vulns/osv_export"
require "vulns/repology"
require "vulns/vulnerability"

module Homebrew
  module Vulns
    # Authoring-time advisory matcher. For a given {Formula} it derives every
    # OSV.dev query key it can (forge repository, language-registry package for
    # the primary URL and each `resource`, distro source packages via
    # {Repology}, CPAN distribution via {CPANSec}), issues *versionless* queries
    # against each, resolves distro advisories to their upstream CVEs, and
    # evaluates each hit's affected range against the version we ship.
    #
    # Runs in `Homebrew/advisory-database` CI and the homebrew-core PR bot to
    # produce candidate `BREW-*` records for human review; never on a user's
    # machine, so request volume is traded for recall and every candidate
    # carries a strategy/confidence label for the reviewer.
    class Match
      include Utils::Output::Mixin

      # Descending precision. When several strategies reach the same CVE the
      # highest is reported as the hit's primary strategy; the rest are kept as
      # supporting evidence.
      STRATEGY_PRECISION = T.let(
        { git: 4, registry: 3, cpansa: 2, distro: 1 }.freeze,
        T::Hash[Symbol, Integer],
      )

      # Recorded in `database_specific.confidence` for the reviewer.
      CONFIDENCE = T.let(
        { git: "high", registry: "high", cpansa: "medium", distro: "low" }.freeze,
        T::Hash[Symbol, String],
      )

      Identity = Struct.new(
        :git_repo, :git_tag, :primary_package, :resource_packages, :distro_packages,
        keyword_init: true
      ) do
        sig { returns(T::Boolean) }
        def identifiable?
          !git_repo.nil? || !primary_package.nil? || resource_packages.any? || distro_packages.any?
        end
      end

      # `ecosystem`/`name` are the OSV `package` fields queried, so a hit's
      # `affected[]` entry can be matched back to this evidence.
      # `subject_version` is the version to evaluate that entry's ranges
      # against: the formula version for the primary source, the pinned
      # resource version for a resource, `nil` for distro (whose versions are
      # not comparable to ours). `advisory` carries the CPANSA record for
      # `:cpansa` evidence so its constraint strings survive to
      # {#range_status}. `source_record` is the {Vulnerability} this evidence
      # was matched against (attached at hit-construction time), so after
      # {#dedup_by_cve} merges hits each evidence still points at the record
      # whose `affected[]` it should be checked against.
      Evidence = Struct.new(:strategy, :ecosystem, :name, :subject_version, :key, :resource,
                            :advisory, :source_record, keyword_init: true) do
        sig { params(record: Vulnerability).returns(T.untyped) }
        def with_source(record)
          source_record ? self : self.class.new(**to_h, source_record: record).freeze
        end
      end

      class Hit
        sig { returns(Vulnerability) }
        attr_reader :vulnerability

        sig { returns(T::Array[Evidence]) }
        attr_reader :evidence

        sig { params(vulnerability: Vulnerability, evidence: T::Array[Evidence]).void }
        def initialize(vulnerability:, evidence:)
          raise ArgumentError, "Hit requires at least one Evidence" if evidence.empty?

          @vulnerability = vulnerability
          @evidence = T.let(
            evidence.map { |e| e.with_source(vulnerability) }
                    .sort_by { |e| -STRATEGY_PRECISION.fetch(e.strategy) }.freeze,
            T::Array[Evidence],
          )
        end

        sig { returns(Evidence) }
        def primary_evidence
          evidence.fetch(0)
        end

        sig { returns(Symbol) }
        def strategy
          primary_evidence.strategy
        end

        sig { returns(T.nilable(String)) }
        def resource
          primary_evidence.resource
        end

        sig { returns(String) }
        def canonical_id
          vulnerability.cve_ids.min || vulnerability.id
        end
      end

      sig { params(repology: T.nilable(Repology), cpan_sec: T.nilable(CPANSec), bulk: T::Boolean).void }
      def initialize(repology: nil, cpan_sec: nil, bulk: false)
        @repology = repology
        @cpan_sec = cpan_sec
        @bulk = bulk
        @vuln_cache = T.let({}, T::Hash[String, T.nilable(Vulnerability)])
        @formula_versions = T.let({}, T::Hash[String, FormulaVersions])
        @formula_rev_lists = T.let({}, T::Hash[String, T::Array[[String, String]]])
      end

      sig { returns(Repology) }
      def repology
        @repology ||= Repology.load
      end

      sig { returns(CPANSec) }
      def cpan_sec
        @cpan_sec ||= CPANSec.load
      end

      sig { params(formula: Formula).returns(Identity) }
      def identify(formula)
        stable = formula.stable
        stable_url = stable&.url
        Identity.new(
          git_repo:          Identify.repo_url(stable_url, formula.head&.url, formula.homepage),
          git_tag:           Identify.tag(stable_url) || stable&.specs&.dig(:tag) || stable&.version&.to_s,
          primary_package:   Identify.registry_package(stable_url),
          resource_packages: formula.resources.filter_map do |r|
            pkg = Identify.registry_package(r.url)
            [r.name, pkg] if pkg
          end.to_h.freeze,
          distro_packages:   distro_packages_for(formula.name),
        ).freeze
      end

      # Returns one {Hit} per distinct vulnerability (grouped by CVE alias)
      # reached by any strategy. Distro-ecosystem records are resolved to their
      # `upstream` CVE(s) so multi-CVE advisories split into per-CVE hits and
      # collapse onto the same CVE reached via GIT/registry. All queries are
      # versionless so historic bump-fixed advisories are returned;
      # {#range_status} evaluates each hit against the shipped version.
      sig { params(formula: Formula).returns(T::Array[Hit]) }
      def advisories_for(formula)
        result = T.let([], T::Array[Hit])
        each_advisory_batch([formula]) { |_, hits| result = hits }
        result
      end

      BULK_CHUNK = 200
      private_constant :BULK_CHUNK

      # Bulk form of {#advisories_for}: builds the labelled queries for a chunk
      # of formulae at once, sends them through a single {OSV.query_batch}
      # (which itself slices at `BATCH_SIZE`), then yields `(formula, hits)` in
      # input order. Per-formula query counts vary widely (one distro entry per
      # ecosystem×srcname), so chunking bounds memory without accumulating the
      # whole tap's queries or records; the `@vuln_cache` still spans chunks.
      sig {
        params(formulae: T::Enumerable[Formula],
               _blk:     T.proc.params(formula: Formula, hits: T::Array[Hit]).void).void
      }
      def each_advisory_batch(formulae, &_blk)
        formulae.each_slice(BULK_CHUNK) do |chunk|
          identities = chunk.map { |f| [f, identify(f)] }
          labelled = T.let([], T::Array[[OSV::Package, [Formula, Evidence]]])
          identities.each do |f, identity|
            next unless identity.identifiable?

            build_osv_queries(identity, f.version.to_s).each do |query, evidence|
              labelled << [query, [f, evidence]]
            end
          end

          by_formula = T.let({}, T::Hash[Formula, T::Hash[String, T::Array[Evidence]]])
          if labelled.any?
            OSV.query_batch(labelled.map(&:first)).each_with_index do |stubs, i|
              formula, evidence = labelled.fetch(i).last
              id_evidence = by_formula[formula] ||= {}
              stubs.each { |stub| (id_evidence[stub.fetch("id")] ||= []) << evidence }
            end
          end

          prefetch_vulnerabilities(by_formula.each_value.flat_map(&:keys))

          identities.each do |f, identity|
            next yield f, [] unless identity.identifiable?

            yield f, hits_from(by_formula[f] || {}, identity)
          end
        end
      end

      sig {
        params(id_evidence: T::Hash[String, T::Array[Evidence]], identity: Identity).returns(T::Array[Hit])
      }
      def hits_from(id_evidence, identity)
        hits = resolve_upstream(id_evidence, identity)
        cpan_evidence(identity).each do |ev|
          cpan_sec.advisories_for(ev.name).each do |adv|
            annotated = Evidence.new(**ev.to_h, advisory: adv).freeze
            if adv.cves.any?
              adv.cves.each do |cve|
                record = fetch_vulnerability(cve) || cpansa_vulnerability(adv, id: cve)
                hits << Hit.new(vulnerability: record, evidence: [annotated])
              end
            else
              hits << Hit.new(vulnerability: cpansa_vulnerability(adv, id: adv.id.to_s),
                              evidence:      [annotated])
            end
          end
        end
        dedup_by_cve(hits)
      end

      # Synthesise a {Vulnerability} for a CPANSA advisory when OSV has no
      # record. `id` is scoped to the single CVE (or CPANSA id) being handled
      # so a multi-CVE advisory whose CVEs are absent from OSV yields distinct
      # records instead of collapsing under the lowest CVE in dedup.
      sig { params(adv: CPANSec::Advisory, id: String).returns(Vulnerability) }
      def cpansa_vulnerability(adv, id:)
        summary = adv.description.to_s.lines.first&.strip
        Vulnerability.new({
          "id"         => id,
          "summary"    => summary,
          "details"    => adv.description,
          "references" => adv.references.map { |u| { "type" => "WEB", "url" => u } },
        }.compact)
      end

      sig {
        params(identity: Identity, formula_version: String).returns(T::Array[[OSV::Package, Evidence]])
      }
      def build_osv_queries(identity, formula_version)
        queries = T.let([], T::Array[[OSV::Package, Evidence]])

        if (repo = identity.git_repo)
          queries << [{ ecosystem: "GIT", name: repo, version: nil },
                      Evidence.new(strategy: :git, ecosystem: "GIT", name: repo,
                                   subject_version: identity.git_tag || formula_version,
                                   key: repo).freeze]
        end

        if (pkg = identity.primary_package) && pkg.ecosystem != "CPAN"
          queries << [{ ecosystem: pkg.ecosystem, name: pkg.name, version: nil },
                      Evidence.new(strategy: :registry, ecosystem: pkg.ecosystem, name: pkg.name,
                                   subject_version: pkg.version, key: pkg.purl).freeze]
        end

        identity.resource_packages.each do |resource, pkg|
          next if pkg.ecosystem == "CPAN"

          queries << [{ ecosystem: pkg.ecosystem, name: pkg.name, version: nil },
                      Evidence.new(strategy: :registry, ecosystem: pkg.ecosystem, name: pkg.name,
                                   subject_version: pkg.version, key: pkg.purl, resource:).freeze]
        end

        identity.distro_packages.each do |ecosystem, srcnames|
          srcnames.each do |srcname|
            queries << [{ ecosystem:, name: srcname, version: nil },
                        Evidence.new(strategy: :distro, ecosystem:, name: srcname,
                                     key: "#{ecosystem}/#{srcname}").freeze]
          end
        end

        queries
      end

      sig { params(identity: Identity).returns(T::Array[Evidence]) }
      def cpan_evidence(identity)
        result = T.let([], T::Array[Evidence])
        primary = identity.primary_package
        if primary&.ecosystem == "CPAN"
          result << Evidence.new(strategy: :cpansa, ecosystem: "CPAN", name: primary.name,
                                 subject_version: primary.version, key: primary.purl)
        end
        identity.resource_packages.each do |resource, pkg|
          next if pkg.ecosystem != "CPAN"

          result << Evidence.new(strategy: :cpansa, ecosystem: "CPAN", name: pkg.name,
                                 subject_version: pkg.version, key: pkg.purl, resource:)
        end
        result
      end

      CVE_ID = /\ACVE-\d{4}-\d+\z/
      private_constant :CVE_ID

      MAX_UPSTREAM_HOPS = 5
      private_constant :MAX_UPSTREAM_HOPS

      # Turn `id => [Evidence, ...]` into `[Hit, ...]`, resolving each record to
      # the CVE(s) it derives from. `upstream` is walked transitively with a
      # per-walk visited set (chains like `USN -> UBUNTU-CVE-* -> CVE-*` occur
      # in practice). `related` links to different vulnerabilities per the OSV
      # schema and is only consulted for its bare CVE ids when `upstream` is
      # empty (AlmaLinux ALSA records use it that way). A record that is
      # already a CVE by id or alias, or that reaches no CVE within the hop
      # budget, is kept as-is. Each resolved hit gains synthesised evidence
      # pointing at our own identity so {#range_status} can check the CVE
      # record's `affected[]` against our version.
      sig {
        params(id_evidence: T::Hash[String, T::Array[Evidence]], identity: Identity)
          .returns(T::Array[Hit])
      }
      def resolve_upstream(id_evidence, identity)
        own = own_evidence(identity)
        hits = T.let([], T::Array[Hit])

        id_evidence.each do |id, evidence|
          record = fetch_vulnerability(id)
          next if record.nil?

          resolved = resolve_to_cves(record, Set[id], MAX_UPSTREAM_HOPS)
          if resolved.empty?
            hits << Hit.new(vulnerability: record, evidence:)
            next
          end

          resolved.each do |cve_record|
            ev = cve_record.equal?(record) ? evidence : evidence + own
            hits << Hit.new(vulnerability: cve_record, evidence: ev)
          end
        end

        hits
      end

      # AlmaLinux ALSA-* records list their source CVEs in `related` rather than
      # `upstream`. That is a data-source quirk; per the OSV schema `related`
      # otherwise names *different* vulnerabilities and must not be traversed.
      RELATED_AS_UPSTREAM_PREFIX = "ALSA-"
      private_constant :RELATED_AS_UPSTREAM_PREFIX

      # Returns the set of CVE records `record` derives from. `[record]` if it
      # is one already; `[]` if the walk exhausts without reaching a CVE (the
      # caller then keeps `record` itself as a low-confidence hit).
      sig {
        params(record: Vulnerability, seen: T::Set[String], budget: Integer)
          .returns(T::Array[Vulnerability])
      }
      def resolve_to_cves(record, seen, budget)
        return [record] if record.cve_ids.any?
        return [] if budget.zero?

        follow = record.upstream.presence
        follow ||= record.related.grep(CVE_ID) if record.id.start_with?(RELATED_AS_UPSTREAM_PREFIX)
        Array(follow).uniq.flat_map do |ref|
          next [] unless seen.add?(ref)

          upstream = fetch_vulnerability(ref)
          upstream ? resolve_to_cves(upstream, seen, budget - 1) : []
        end.uniq(&:id)
      end

      # Evidence rows pointing at our own identity keys (git repo, primary
      # registry package) with the formula/package version as subject. Attached
      # to distro-resolved upstream hits so {#range_status} can evaluate the
      # upstream CVE record's `affected[]` against something comparable.
      sig { params(identity: Identity).returns(T::Array[Evidence]) }
      def own_evidence(identity)
        result = T.let([], T::Array[Evidence])
        if (repo = identity.git_repo)
          result << Evidence.new(strategy: :distro, ecosystem: "GIT", name: repo,
                                 subject_version: identity.git_tag, key: "upstream:#{repo}").freeze
        end
        if (pkg = identity.primary_package)
          result << Evidence.new(strategy: :distro, ecosystem: pkg.ecosystem, name: pkg.name,
                                 subject_version: pkg.version, key: "upstream:#{pkg.purl}").freeze
        end
        result
      end

      # Bulk mode (the `--all` sweep) trusts the published index; only a
      # single-formula run (the PR bot, or an explicit named check) may hit the
      # live Repology API for a formula the index doesn't yet cover.
      sig { params(name: String).returns(Repology::DistroMap) }
      def distro_packages_for(name)
        indexed = repology.distro_packages_for(name)
        return indexed if indexed.any? || @bulk

        Repology.lookup(name)
      rescue CachedFeed::Error => e
        odebug "Repology lookup for #{name} failed: #{e.message}"
        {}
      end

      MAX_VULN_FETCH_THREADS = 15
      private_constant :MAX_VULN_FETCH_THREADS

      # OSV `querybatch` returns id/modified stubs. Warm `@vuln_cache` with the
      # full records for a chunk's stub ids before per-formula processing so
      # {#resolve_upstream} reads mostly from cache.
      sig { params(ids: T::Array[String]).void }
      def prefetch_vulnerabilities(ids)
        missing = ids.uniq.reject { |id| @vuln_cache.key?(id) }
        missing.each_slice(MAX_VULN_FETCH_THREADS) do |slice|
          slice.map { |id| [id, Thread.new { load_vulnerability(id) }] }
               .each { |id, t| @vuln_cache[id] = t.value }
        end
      end

      sig { params(id: String).returns(T.nilable(Vulnerability)) }
      def fetch_vulnerability(id)
        @vuln_cache.fetch(id) { @vuln_cache[id] = load_vulnerability(id) }
      end

      sig { params(id: String).returns(T.nilable(Vulnerability)) }
      def load_vulnerability(id)
        Vulnerability.new(OSV.vulnerability(id))
      rescue OSV::Error => e
        odebug "OSV.vulnerability(#{id}) failed: #{e.message}"
        nil
      end

      sig { params(hits: T::Array[Hit]).returns(T::Array[Hit]) }
      def dedup_by_cve(hits)
        hits.group_by(&:canonical_id).map do |_, group|
          next group.fetch(0) if group.one?

          primary = T.must(group.max_by { |h| STRATEGY_PRECISION.fetch(h.strategy) })
          Hit.new(vulnerability: primary.vulnerability,
                  evidence:      group.flat_map(&:evidence).uniq)
        end
      end

      # Evaluate `hit` against every evidence's subject, each against the
      # record that evidence was matched against, and aggregate: `:affected` if
      # any subject is affected (a fixed primary must not hide an affected
      # resource, or vice versa), else `:fixed` if any is fixed, else
      # `:not_applicable` only when every comparable subject says so. Returns
      # `[status, evidence]` where `evidence` is the one whose result was
      # chosen (used by {#first_fixed_version} and for the emitted record's
      # resource attribution), or `nil` if no evidence produced a checkable
      # answer.
      sig { params(hit: Hit).returns(T.nilable([Vulnerability::RangeStatus, Evidence])) }
      def range_status(hit)
        results = hit.evidence.filter_map do |ev|
          status = evidence_range_status(ev, ev.subject_version)
          [status, ev] if status
        end
        return if results.empty?

        results.find { |s, _| s.affected? } ||
          results.find { |s, _| s.fixed? } ||
          results.first
      end

      sig {
        params(evidence: Evidence, subject_version: T.nilable(String))
          .returns(T.nilable(Vulnerability::RangeStatus))
      }
      def evidence_range_status(evidence, subject_version)
        return if subject_version.nil?

        if evidence.strategy == :cpansa
          adv = evidence.advisory
          CPANSec.range_status(adv, subject_version) if adv
        else
          evidence.source_record&.range_status(evidence.ecosystem, evidence.name, subject_version)
        end
      end

      # Emit a candidate `BREW-*` OSV record for `hit` against `formula`.
      #
      # `first_fixed` is the {PkgVersion} at which Homebrew first shipped a fix
      # (from {#first_fixed_version} or a hand-set value). Otherwise
      # {#range_status} is consulted: `affected? == false` sets
      # `fixed: pkg_version` and `ecosystem_specific.fix: "bump"`;
      # `affected? == true` (or no comparable range) emits no `fixed` event and
      # `fix: null`. As with {OsvExport.record_for}, {OsvExport.merge_existing}
      # preserves on-disk `ranges` on rewrite so a hand-corrected boundary
      # sticks.
      sig {
        params(formula: Formula, hit: Hit, first_fixed: T.nilable(String), now: Time)
          .returns(T::Hash[Symbol, T.untyped])
      }
      def to_brew_record(formula, hit, first_fixed: nil, now: Time.now.utc)
        vuln = hit.vulnerability
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        status, status_evidence = range_status(hit)

        fixed = first_fixed
        fixed ||= formula.pkg_version.to_s if status&.fixed?
        events = T.let([{ introduced: "0" }], T::Array[T::Hash[Symbol, String]])
        events << { fixed: } if fixed

        record = T.let({
          schema_version:    OsvExport::SCHEMA_VERSION,
          id:                "#{OsvExport::ID_PREFIX}-#{formula.name}-#{hit.canonical_id}",
          published:         timestamp,
          modified:          timestamp,
          upstream:          vuln.identifiers,
          affected:          [affected_entry(formula, hit, events, fixed, status, status_evidence)],
          database_specific: {
            source:            "matched",
            strategy:          hit.strategy.to_s,
            confidence:        confidence_for(hit, status),
            upstream_evidence: hit.evidence.map { |e| e.to_h.except(:advisory, :source_record).compact },
          },
        }, T::Hash[Symbol, T.untyped])

        record[:summary] = vuln.summary if vuln.summary
        record[:details] = vuln.details if vuln.details
        record[:severity] = vuln.severity_entries if vuln.severity_entries.any?
        if (refs = vuln.references).any?
          record[:references] = refs.uniq { |r| [r["type"], URI::RFC2396_PARSER.unescape(r["url"].to_s)] }
        end

        record
      end

      sig {
        params(hit: Hit, status: T.nilable(Vulnerability::RangeStatus)).returns(String)
      }
      def confidence_for(hit, status)
        base = CONFIDENCE.fetch(hit.strategy)
        return base if status

        # No comparable range: the reviewer must set the boundary by hand.
        (base == "high") ? "medium" : "low"
      end

      sig {
        params(formula: Formula, hit: Hit, events: T::Array[T::Hash[Symbol, String]],
               fixed: T.nilable(String), status: T.nilable(Vulnerability::RangeStatus),
               status_evidence: T.nilable(Evidence))
          .returns(T::Hash[Symbol, T.untyped])
      }
      def affected_entry(formula, hit, events, fixed, status, status_evidence)
        eco = T.let({ fix: fixed ? "bump" : nil }, T::Hash[Symbol, T.nilable(String)])
        eco[:range_state] = status.state.to_s if status
        eco[:upstream_fixed_in] = status.fixed_in if status&.fixed_in
        # Attribute the resource whose subject decided the state, falling back
        # to the highest-precision evidence when nothing was comparable.
        if (resource = status_evidence&.resource || hit.resource)
          eco[:resource] = resource
          eco[:resource_purl] = (status_evidence if status_evidence&.resource)&.key ||
                                hit.evidence.find { |e| e.resource == resource }&.key
        end
        {
          package:            {
            ecosystem: OsvExport::ECOSYSTEM,
            name:      formula.name,
            purl:      OsvExport.purl(formula.name),
          },
          ranges:             [{ type: "ECOSYSTEM", events: }],
          ecosystem_specific: eco,
        }
      end

      # Walk homebrew-core git history (newest first) via {FormulaVersions} and
      # return the `pkg_version` at the oldest revision where the aggregate of
      # every checkable subject is still `:fixed`. Re-running the full
      # per-evidence range check with each revision's subject versions keeps
      # `last_affected` and exclusive-bound semantics intact and stops as soon
      # as any subject (primary or a resource) drops back into `:affected`, so
      # a primary fixed at 2.0 with a resource fixed at 3.0 yields 3.0.
      #
      # Returns:
      # - `nil` when the current aggregate is not `:fixed`.
      # - `:never_affected` when the walk reaches `:not_applicable` (or the
      #   start of the formula's history) without ever seeing `:affected`,
      #   i.e. Homebrew jumped from a version below `introduced` straight past
      #   `fixed` and never shipped an affected build. The caller drops the
      #   candidate rather than emitting `{introduced: "0", fixed: <first>}`.
      # - a `pkg_version` String when the walk hits `:affected`, or when it
      #   stops at an unloadable revision (best-effort boundary; the reviewer
      #   can tighten).
      #
      # The rev-list and per-revision loads are cached per formula.
      sig { params(formula: Formula, hit: Hit).returns(T.nilable(T.any(String, Symbol))) }
      def first_fixed_version(formula, hit)
        return unless range_status(hit)&.first&.fixed?

        fv = @formula_versions[formula.name] ||= FormulaVersions.new(formula)
        revs = @formula_rev_lists[formula.name] ||=
          [].tap { |a| fv.rev_list("HEAD") { |rev, entry| a << [rev, entry] } }

        last_fixed = T.let(formula.pkg_version.to_s, String)
        revs.each do |rev, entry|
          state = fv.formula_at_revision(rev, entry) do |old|
            [aggregate_state_at(old, hit), old.pkg_version.to_s]
          end
          # `nil` means the revision failed to load; can't verify further.
          return last_fixed if state.nil?

          aggregate, pkg_version = state
          return :never_affected if aggregate == :not_applicable
          return last_fixed if aggregate != :fixed

          last_fixed = pkg_version
        end
        :never_affected
      end

      sig { params(formula: Formula, hit: Hit).returns(T.nilable(Symbol)) }
      def aggregate_state_at(formula, hit)
        results = hit.evidence.filter_map do |ev|
          # Evidence built without a subject_version (distro queries, own-
          # identity rows for a formula with no derivable tag) is deliberately
          # uncheckable and must stay that way at historical revisions too;
          # substituting the historical formula version would compare it
          # against the distro record's distro-versioned range.
          next if ev.subject_version.nil?

          subject = subject_version(formula, ev.resource)&.to_s
          evidence_range_status(ev, subject)
        end
        return if results.empty?
        return :affected if results.any?(&:affected?)
        return :fixed if results.any?(&:fixed?)

        :not_applicable
      end

      sig { params(formula: Formula, resource: T.nilable(String)).returns(T.nilable(Version)) }
      def subject_version(formula, resource)
        if resource
          begin
            formula.resource(resource)&.version
          rescue ResourceMissingError
            nil
          end
        else
          formula.version
        end
      end
    end
  end
end
