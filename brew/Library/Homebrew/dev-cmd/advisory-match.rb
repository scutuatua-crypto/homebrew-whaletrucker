# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "formula"
require "vulns/match"

module Homebrew
  module DevCmd
    class AdvisoryMatch < AbstractCommand
      cmd_args do
        description <<~EOS
          Match <formula> against OSV.dev (GIT, language-registry and distro
          ecosystems) and CPANSA to produce candidate `BREW-*` advisory records
          for <https://github.com/Homebrew/advisory-database>.

          This is authoring-time tooling for the advisory-database CI and the
          `homebrew-core` PR bot; use `brew vulns` to scan installed formulae.
        EOS
        switch "--all",
               description: "Match every formula in `homebrew/core`."
        switch "--index",
               description: "Emit the formula-identity index as JSON and exit."
        switch "--json",
               description: "Output candidate records as a JSON array."
        flag   "--output=",
               description: "Write each record to <directory> as " \
                            "`BREW-<formula>-<id>.json`, preserving existing " \
                            "`published`/`ranges` fields."
        switch "--no-history",
               description: "Skip the `FormulaVersions` walk for the `fixed` " \
                            "boundary; use the current `pkg_version` instead."
        conflicts "--all", "--index"
        conflicts "--all", "--json"
        conflicts "--index", "--json"
        conflicts "--index", "--output"

        named_args [:formula]

        hide_from_man_page!
      end

      sig { override.void }
      def run
        Formulary.enable_factory_cache!
        Homebrew.with_no_api_env do
          latest_macos = MacOSVersion.new((HOMEBREW_MACOS_NEWEST_UNSUPPORTED.to_i - 1).to_s).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            matcher = Homebrew::Vulns::Match.new(bulk: args.all? || args.index?)
            next emit_index(matcher) if args.index?

            emitter = build_emitter
            begin
              matcher.each_advisory_batch(each_formula) do |formula, hits|
                report(matcher, formula, hits) if text_mode?
                hits.each do |hit|
                  # A `:not_applicable` hit (below every `introduced`) emitted
                  # as `{introduced: 0}` with no `fixed` reads to OSV consumers
                  # as currently affected; drop it instead.
                  status, = matcher.range_status(hit)
                  next if status&.state == :not_applicable

                  first_fixed = matcher.first_fixed_version(formula, hit) unless args.no_history?
                  next if first_fixed == :never_affected

                  boundary = first_fixed if first_fixed.is_a?(String)
                  emitter << matcher.to_brew_record(formula, hit, first_fixed: boundary)
                end
              end
            rescue Homebrew::Vulns::OSV::Error => e
              onoe "OSV query failed: #{e.message}"
              Homebrew.failed = true
            end
            emitter.finish
          end
        end
      end

      sig { returns(T::Enumerator[Formula]) }
      def each_formula
        return args.named.to_resolved_formulae.each unless args.all?

        raise UsageError, "`--all` does not take named arguments" if args.named.any?

        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        Enumerator.new do |y|
          tap.formula_names.each do |name|
            y << Formulary.factory(name)
          rescue => e
            onoe "Error loading formula '#{name}': #{e}"
          end
        end
      end

      sig { returns(T::Boolean) }
      def text_mode?
        !args.json? && args.output.nil?
      end

      sig {
        params(matcher: Homebrew::Vulns::Match, formula: Formula,
               hits: T::Array[Homebrew::Vulns::Match::Hit]).void
      }
      def report(matcher, formula, hits)
        ohai "#{formula.name} #{formula.pkg_version}"
        if hits.empty?
          puts "  No advisories matched."
          return
        end
        hits.sort_by { |h| [-h.vulnerability.severity_level, h.canonical_id] }.each do |hit|
          v = hit.vulnerability
          status, = matcher.range_status(hit)
          state = case status&.state
          when nil       then "uncomparable"
          when :affected then "AFFECTED#{", upstream fix #{status&.fixed_in}" if status&.fixed_in}"
          when :fixed    then "fixed (upstream #{status&.fixed_in || "?"})"
          else "not applicable"
          end
          summary = v.summary&.slice(0, 60)
          puts "  #{hit.canonical_id} [#{hit.strategy}, #{matcher.confidence_for(hit, status)}] " \
               "#{v.severity_display} #{state}" \
               "#{" (resource: #{hit.resource})" if hit.resource}" \
               "#{" — #{summary}" if summary}"
        end
      end

      # `--output` and text mode write per-record and only accumulate counts;
      # `--json` accumulates the array (single-formula / PR-bot use, so bounded).
      class Emitter
        sig { params(record: T::Hash[Symbol, T.untyped]).void }
        def <<(record); end

        sig { void }
        def finish; end
      end

      class DirEmitter < Emitter
        sig { params(dir: String, verbose: T::Boolean).void }
        def initialize(dir, verbose:)
          super()
          FileUtils.mkdir_p(dir)
          @dir = dir
          @verbose = verbose
          @written = T.let(0, Integer)
          @unchanged = T.let(0, Integer)
          @skipped_generated = T.let(0, Integer)
        end

        sig { override.params(record: T::Hash[Symbol, T.untyped]).void }
        def <<(record)
          path = File.join(@dir, "#{record.fetch(:id)}.json")
          # A record already emitted by `generate-vulns-advisories` (a formula
          # `resolves` patch annotation) is more authoritative than a matched
          # candidate; overwriting it would drop `fix: "patch"` for a derived
          # `fix: null`/`"bump"`.
          if File.file?(path) && existing_source(path) == "generated"
            @skipped_generated += 1
            return
          end
          merged = Homebrew::Vulns::OsvExport.merge_existing(path, record)
          if merged.nil?
            @unchanged += 1
            return
          end
          File.write(path, "#{JSON.pretty_generate(merged)}\n")
          puts "  wrote #{path}" if @verbose
          @written += 1
        end

        sig { params(path: String).returns(T.nilable(String)) }
        def existing_source(path)
          JSON.parse(File.read(path)).dig("database_specific", "source")
        rescue JSON::ParserError
          nil
        end

        sig { override.void }
        def finish
          Utils::Output.ohai "#{@written} records written to #{@dir} " \
                             "(#{@unchanged} unchanged, #{@skipped_generated} generated left as-is)"
        end
      end

      class JsonEmitter < Emitter
        sig { void }
        def initialize
          super
          @records = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
        end

        sig { override.params(record: T::Hash[Symbol, T.untyped]).void }
        def <<(record)
          @records << record
        end

        sig { override.void }
        def finish
          puts JSON.pretty_generate(@records)
        end
      end

      class CountEmitter < Emitter
        sig { void }
        def initialize
          super
          @count = T.let(0, Integer)
        end

        sig { override.params(_record: T::Hash[Symbol, T.untyped]).void }
        def <<(_record)
          @count += 1
        end

        sig { override.void }
        def finish
          Utils::Output.ohai "#{@count} candidate records"
        end
      end

      sig { returns(Emitter) }
      def build_emitter
        if (dir = args.output)
          DirEmitter.new(dir, verbose: args.verbose?)
        elsif args.json?
          JsonEmitter.new
        else
          CountEmitter.new
        end
      end

      sig { params(matcher: Homebrew::Vulns::Match).void }
      def emit_index(matcher)
        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        index = tap.formula_names.each_with_object({}) do |name, h|
          identity = matcher.identify(Formulary.factory(name))
          next unless identity.identifiable?

          h[name] = {
            git_repo:          identity.git_repo,
            git_tag:           identity.git_tag,
            primary_package:   identity.primary_package&.to_h,
            resource_packages: identity.resource_packages.transform_values(&:to_h),
            distro_packages:   identity.distro_packages,
          }.compact
        rescue => e
          onoe "Error loading formula '#{name}': #{e}"
        end
        puts JSON.pretty_generate(index)
      end
    end
  end
end
