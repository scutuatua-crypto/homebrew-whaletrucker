# typed: strict
# frozen_string_literal: true

require "fileutils"
require "env_config"
require "system_command"
require "utils/popen"
require "utils/github/actions"
require "extend/os/linux/sandbox/backend"

class Sandbox
  class Bubblewrap < LinuxBackend
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    EXECUTABLE = "bwrap"
    TEST_ARGS = [
      "--unshare-user",
      "--unshare-ipc",
      "--unshare-pid",
      "--unshare-uts",
      "--unshare-cgroup-try",
      "--ro-bind", "/", "/",
      "--proc", "/proc",
      "--dev", "/dev",
      "true"
    ].freeze
    SYSTEM_PATHS = %w[
      /usr/bin
      /bin
    ].freeze
    HOMEBREW_PATHS = [
      "#{HOMEBREW_PREFIX}/bin",
    ].freeze
    NESTED_ERROR = "Creating new namespace failed: nesting depth or /proc/sys/user/max_*_namespaces exceeded"
    class SysctlSetting < T::Struct
      const :assignment, String
      const :description, T::Array[String]
      const :optional, T::Boolean, default: false
    end
    # These settings mirror the `sysctl` assignments in
    # Library/Homebrew/cmd/setup-sandbox.sh; keep both in sync.
    SYSCTL_SETTINGS = T.let([
      SysctlSetting.new(
        assignment:  "kernel.unprivileged_userns_clone=1",
        description: [
          "Allows unprivileged processes to create user namespaces. Rootless",
          "Bubblewrap needs this to isolate builds without elevated privileges.",
        ],
      ),
      SysctlSetting.new(
        assignment:  "user.max_user_namespaces=28633",
        description: [
          "Allows each user to allocate enough user namespaces. A zero or low",
          "limit can prevent Bubblewrap from creating its sandbox.",
        ],
      ),
      SysctlSetting.new(
        assignment:  "kernel.apparmor_restrict_unprivileged_userns=0",
        description: [
          "Allows unprivileged user namespaces on AppArmor-enabled systems",
          "that restrict them by default. Older kernels may not provide this",
          "setting.",
        ],
        optional:    true,
      ),
    ].freeze, T::Array[SysctlSetting])
    # Per-distro Bubblewrap install commands, detected by package manager and
    # checked in priority order. Mirrors the build tools instructions in
    # `Homebrew/install`'s `install.sh`.
    INSTALL_COMMANDS = T.let({
      "apt-get" => "sudo apt-get install bubblewrap",
      "dnf"     => "sudo dnf install bubblewrap",
      "yum"     => "sudo yum install bubblewrap",
      "pacman"  => "sudo pacman -S bubblewrap",
      "apk"     => "sudo apk add bubblewrap",
    }.freeze, T::Hash[String, String])
    private_constant :EXECUTABLE, :TEST_ARGS, :SYSTEM_PATHS, :HOMEBREW_PATHS, :NESTED_ERROR, :SysctlSetting,
                     :SYSCTL_SETTINGS, :INSTALL_COMMANDS

    class << self
      sig { returns(String) }
      def executable_name
        EXECUTABLE
      end

      sig { params(candidate: ::Pathname).returns(T::Boolean) }
      def executable_usable?(candidate)
        !File.stat(candidate).setuid?
      end

      sig { returns(T::Array[String]) }
      def system_paths
        SYSTEM_PATHS
      end

      sig { returns(::PATH) }
      def executable_candidate_paths
        PATH.new(HOMEBREW_PATHS, system_paths, ORIGINAL_PATHS, ENV.fetch("PATH"), HOMEBREW_ORIGINAL_BREW_FILE.dirname)
      end

      sig { returns(T.nilable(::Pathname)) }
      def executable
        executable_candidate_paths.each do |path|
          begin
            candidate = ::Pathname.new(File.expand_path(executable_name, path))
          rescue ArgumentError
            next
          end

          next if !candidate.file? || !candidate.executable?
          next unless executable_usable?(candidate)

          return candidate
        end

        nil
      end

      sig { returns(::Pathname) }
      def executable!
        executable || raise("Bubblewrap is required to use the Linux sandbox.")
      end

      sig { params(install_from_tests: T::Boolean).void }
      def ensure_installed!(install_from_tests: false)
        return unless Homebrew::EnvConfig.sandbox_linux?
        return if ENV["HOMEBREW_TESTS"] && !install_from_tests
        return if ENV["HOMEBREW_INSTALLING_BUBBLEWRAP"]
        return if executable

        begin
          require "exceptions"
          require "formula"
          with_env(HOMEBREW_INSTALLING_BUBBLEWRAP: "1") do
            ::Formula["bubblewrap"].ensure_installed!(reason: "Linux sandboxing")
          end
          reset_state!
          return if executable
        rescue ::FormulaUnavailableError
          nil
        end

        return unless GitHub::Actions.env_set?
        return unless ENV.fetch("HOMEBREW_GITHUB_HOSTED_RUNNER", nil)
        return unless which("apt-get")

        ohai "Installing Bubblewrap..."
        command = ["apt-get", "install", "--yes", "bubblewrap"]
        command.unshift("sudo") unless Process.euid.zero?
        system(*command)
        reset_state!
      end

      sig { returns(T::Boolean) }
      def available?
        state == :available
      end

      # Bubblewrap reports this specific namespace error when an outer
      # Bubblewrap sandbox prevents Homebrew from creating another rootless
      # sandbox. The shared `avoid_nested_sandboxing?` only calls this once the
      # `$HOMEBREW_AVOID_NESTED_SANDBOXING` opt-in is set.
      sig { returns(T::Boolean) }
      def nested_sandbox?
        return false unless Homebrew::EnvConfig.sandbox_linux?

        bubblewrap = executable
        return false unless bubblewrap

        Utils.popen_read(bubblewrap.to_s, *TEST_ARGS, err: :out).include?(NESTED_ERROR)
      end

      sig { returns(Symbol) }
      def state
        return :config_disabled unless Homebrew::EnvConfig.sandbox_linux?

        @state ||= T.let(compute_state, T.nilable(Symbol))
      end

      sig { void }
      def reset_state!
        @state = T.let(nil, T.nilable(Symbol))
      end

      sig { returns(T::Array[String]) }
      def configuration_commands
        SYSCTL_SETTINGS.map do |setting|
          command = "sudo sysctl -w #{setting.assignment}"
          command += " || true" if setting.optional
          command
        end
      end

      sig { returns(T::Array[String]) }
      def configuration_command_messages
        commands = configuration_commands
        SYSCTL_SETTINGS.each_with_index.flat_map do |setting, index|
          [
            "  #{commands.fetch(index)}",
            *setting.description.map { |line| "    #{line}" },
          ]
        end
      end

      sig { void }
      def configure!
        unless executable
          ensure_installed!(install_from_tests: true)
          unless executable
            reset_state!
            return
          end
        end

        ohai "Configuring Bubblewrap..."
        command = [HOMEBREW_BREW_FILE.to_s, "setup-sandbox"]
        command.unshift("sudo") unless Process.euid.zero?
        raise ErrorDuringExecution.new(command, status: $CHILD_STATUS || 1) unless system(*command)

        reset_state!
      end

      sig { returns(T.nilable(String)) }
      def failure_reason
        case state
        when :config_disabled, :available
          nil
        when :missing
          "Bubblewrap is required to use the Linux sandbox but was not found."
        when :setuid
          "A rootless Bubblewrap executable is required to use the Linux sandbox, " \
          "but all found `bwrap` executables are setuid."
        when :unavailable
          "Bubblewrap is installed but cannot create a rootless sandbox."
        else
          "The Linux sandbox is not available."
        end
      end

      sig { returns(T.nilable(String)) }
      def install_command
        INSTALL_COMMANDS.find { |package_manager, _| which(package_manager) }&.last
      end

      private

      sig { returns(Symbol) }
      def compute_state
        bubblewraps = executables
        return :missing if bubblewraps.empty?

        bubblewraps = bubblewraps.select { |candidate| executable_usable?(candidate) }
        return :setuid if bubblewraps.empty?

        return :available if bubblewraps.any? { |candidate| sandbox_available?(candidate) }

        :unavailable
      end

      sig { returns(T::Array[::Pathname]) }
      def executables
        executable_candidate_paths.filter_map do |path|
          begin
            candidate = ::Pathname.new(File.expand_path(executable_name, path))
          rescue ArgumentError
            next
          end

          candidate if candidate.file? && candidate.executable?
        end
      end

      sig { params(bubblewrap: ::Pathname).returns(T::Boolean) }
      def sandbox_available?(bubblewrap)
        result = system_command(
          bubblewrap,
          args:         TEST_ARGS,
          print_stderr: false,
        )
        return true if result.success?

        opoo "bubblewrap test probe failed"
        $stderr.print result.merged_output
        false
      end
    end

    sig { params(profile: SandboxProfile).void }
    def initialize(profile)
      super
      @masked_read_paths = T.let([], T::Array[::Pathname])
    end

    sig { params(block: T.proc.void).void }
    def run(&block)
      old_report_on_exception = T.let(Thread.report_on_exception, T.nilable(T::Boolean))
      Thread.report_on_exception = false
      super
    ensure
      Thread.report_on_exception = old_report_on_exception unless old_report_on_exception.nil?
      @masked_read_paths.reverse_each { |path| FileUtils.rm_rf(path) }
      @masked_read_paths.clear
    end

    sig { params(args: T::Array[T.any(String, ::Pathname)], tmpdir: String).returns(T::Array[T.any(String, ::Pathname)]) }
    def command(args, tmpdir)
      [self.class.executable!, *arguments(tmpdir), "--", *args]
    end

    sig { params(tmpdir: String).returns(T::Array[String]) }
    def arguments(tmpdir)
      args = T.let([
        "--unshare-user",
        "--unshare-ipc",
        "--unshare-pid",
        "--unshare-uts",
        "--unshare-cgroup-try",
        "--die-with-parent",
        "--new-session",
        "--ro-bind", "/", "/",
        "--dev", "/dev",
        "--proc", "/proc"
      ], T::Array[String])
      args << "--unshare-net" if deny_all_network?

      writable_paths.each do |path, type|
        prepare_writable_path(path, type)
        args += ["--bind", path, path]
      end

      denied_write_paths.each do |path|
        next unless File.exist?(path)

        args += ["--ro-bind", path, path]
      end

      denied_read_paths.each do |path|
        next unless File.exist?(path)

        args += if File.directory?(path)
          ["--bind", masked_read_path, path]
        else
          ["--ro-bind", File::NULL, path]
        end
      end

      args += ["--bind", tmpdir, tmpdir, "--chdir", tmpdir]

      args
    end

    private

    sig { returns(T::Array[String]) }
    def denied_write_paths
      profile_paths(allow: false, operation: "file-write")
    end

    sig { returns(T::Array[String]) }
    def denied_read_paths
      profile_paths(allow: false, operation: "file-read")
    end

    sig { returns(String) }
    def masked_read_path
      path = ::Pathname.new(Dir.mktmpdir("homebrew-sandbox-deny-read", HOMEBREW_TEMP))
      @masked_read_paths << path
      path.to_s
    end
  end
end
