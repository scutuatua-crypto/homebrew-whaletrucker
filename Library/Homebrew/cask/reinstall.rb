# typed: strict
# frozen_string_literal: true

require "utils/output"
require "install"

module Cask
  class Reinstall
    extend ::Utils::Output::Mixin

    sig {
      params(
        casks: ::Cask::Cask, verbose: T::Boolean, force: T::Boolean, skip_cask_deps: T::Boolean, binaries: T::Boolean,
        require_sha: T::Boolean, zap: T::Boolean, skip_prefetch: T::Boolean,
        download_queue: T.nilable(Homebrew::DownloadQueue)
      ).void
    }
    def self.reinstall_casks(
      *casks,
      verbose: false,
      force: false,
      skip_cask_deps: false,
      binaries: false,
      require_sha: false,
      zap: false,
      skip_prefetch: false,
      download_queue: nil
    )
      require "cask/installer"

      created_download_queue = T.let(false, T::Boolean)
      if download_queue.nil?
        if skip_prefetch
          download_queue = Homebrew.default_download_queue
        else
          download_queue = Homebrew::DownloadQueue.new(pour: true)
          created_download_queue = true
        end
      end

      cask_installers = T.let([], T::Array[Installer])
      begin
        cask_installers = casks.map do |cask|
          Installer.new(
            cask,
            binaries:,
            verbose:,
            force:,
            skip_cask_deps:,
            require_sha:,
            reinstall:      true,
            zap:,
            download_queue:,
            defer_fetch:    true,
          )
        end

        unless skip_prefetch
          Homebrew::Install.enqueue_cask_installers(cask_installers, download_queue:)
          download_queue.fetch(
            heading: Homebrew::Install.combined_fetch_downloads_heading(cask_names: casks.map(&:full_name)),
          )
        end
      ensure
        download_queue.shutdown if created_download_queue
      end

      exit 1 if Homebrew.failed?

      caught_exceptions = []

      cask_installers.each do |installer|
        installer.install
      rescue => e
        caught_exceptions << e
        next
      end

      return if caught_exceptions.empty?

      raise MultipleCaskErrors, caught_exceptions if caught_exceptions.count > 1

      raise caught_exceptions.fetch(0)
    end
  end
end
