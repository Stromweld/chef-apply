#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef_apply/telemeter"
require "chef_apply/error"

module ChefApply
  module Action
    # Derive new Actions from Action::Base
    # "target_host" is a TargetHost that the action is being applied to. May be nil
    #               if the action does not require a target.
    # "config" is hash containing any options that your command may need
    #
    # Implement perform_action to perform whatever action your class is intended to do.
    # Run time will be captured via telemetry and categorized under ":action" with the
    # unqualified class name of your Action.
    class Base
      attr_reader :target_host, :config

      def initialize(config = {})
        c = config.dup
        @target_host = c.delete :target_host
        # Remaining options are for child classes to make use of.
        @config = c
      end

      run_report = "$env:APPDATA/chef-workstation/cache/run-report.json"
      PATH_MAPPING = {
        chef_client: {
          windows: "cmd /c C:/opscode/chef/bin/chef-client",
          other: "/opt/chef/bin/chef-client",
        },
        cache_path: {
          windows: '#{ENV[\'APPDATA\']}/chef-workstation',
          other: "/var/chef-workstation",
        },
        read_chef_report: {
          windows: "type #{run_report}",
          other: "cat /var/chef-workstation/cache/run-report.json",
        },
        delete_chef_report: {
          windows: "If (Test-Path #{run_report}){ Remove-Item -Force -Path #{run_report} }",
          other: "rm -f /var/chef-workstation/cache/run-report.json",
        },
        tempdir: {
          windows: "%TEMP%",
          other: "$TMPDIR",
        },
        delete_folder: {
          windows: "Remove-Item -Recurse -Force –Path",
          other: "rm -rf",
        },
      }.freeze

      # TODO - I'd like to consider PATH_MAPPING in action::base
      #        to platform subclasses/mixins for target_host.  This way our 'target host'
      #        which reprsents a node, the data and actions we can perform on it
      #        knows how to `read_chef_report`, `mkdir`, etc.
      #        -mp 2018-10-17

      PATH_MAPPING.keys.each do |m|
        define_method(m) { PATH_MAPPING[m][family] }
      end

      # Chef will try 'downloading' the policy from the internet unless we pass it a valid, local file
      # in the working directory. By pointing it at a local file it will just copy it instead of trying
      # to download it.
      #
      # Chef 13 on Linux requires full path specifiers for --config and --recipe-url while on Chef 13 and 14 on
      # Windows must use relative specifiers to prevent URI from causing an error
      # (https://github.com/chef/chef/pull/7223/files).
      def run_chef(working_dir, config_file, policy)
        case family
        when :windows
          "Set-Location -Path #{working_dir}; " +
            # We must 'wait' for chef-client to finish before changing directories and Out-Null does that
            "chef-client -z --config #{File.join(working_dir, config_file)} --recipe-url #{File.join(working_dir, policy)} | Out-Null; " +
            # We have to leave working dir so we don't hold a lock on it, which allows us to delete this tempdir later
            "Set-Location C:/; " +
            "exit $LASTEXITCODE"
        else
          # cd is shell a builtin, so much call bash. This also means all commands are executed
          # with sudo (as long as we are hardcoding our sudo use)
          "bash -c 'cd #{working_dir}; chef-client -z --config #{File.join(working_dir, config_file)} --recipe-url #{File.join(working_dir, policy)}'"
        end
      end

      # Trying to perform File or Pathname operations on a Windows path with '\'
      # characters in it fails. So lets convert them to '/' which these libraries
      # handle better.
      def escape_windows_path(p)
        if family == :windows
          p = p.tr("\\", "/")
        end
        p
      end

      def run(&block)
        @notification_handler = block
        Telemeter.timed_action_capture(self) do
          begin
            perform_action
          rescue StandardError => e
            # Give the caller a chance to clean up - if an exception is
            # raised it'll otherwise get routed through the executing thread,
            # providing no means of feedback for the caller's current task.
            notify(:error, e)
            @error = e
          end
        end
        # Raise outside the block to ensure that the telemetry cpature completes
        raise @error unless @error.nil?
      end

      def name
        self.class.name.split("::").last
      end

      def perform_action
        raise NotImplemented
      end

      def notify(action, *args)
        return if @notification_handler.nil?
        ChefApply::Log.debug("[#{self.class.name}] Action: #{action}, Action Data: #{args}")
        @notification_handler.call(action, args) if @notification_handler
      end

      private

      def family
        @family ||= begin
          f = target_host.platform.family
          if f == "windows"
            :windows
          else
            :other
          end
        end
      end
    end
  end
end
