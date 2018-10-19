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

module ChefApply::Action::InstallChef
  class Linux < ChefApply::Action::InstallChef::Base
    def install_chef_to_target(remote_path)
      install_cmd = case File.extname(remote_path)
                    when ".rpm"
                      "rpm -Uvh #{remote_path}"
                    when ".deb"
                      "dpkg -i #{remote_path}"
                    end
      target_host.run_command!(install_cmd)
      nil
    end

    def setup_remote_temp_path
      installer_dir = "/tmp/chef-installer"
      target_host.mkdir(installer_dir)
      installer_dir
    end
  end
end
