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

require "r18n-desktop"

# A very thin wrapper around R18n, the idea being that we're likely to replace r18n
# down the road and don't want to have to change all of our commands.
module ChefApply
  class Text
    R18n.from_env(File.join(File.dirname(__FILE__), "../..", "i18n/"))
    t = R18n.get.t
    t.translation_keys.each do |k|
      k = k.to_sym
      define_singleton_method k do |*args|
        TextWrapper.new(t.send(k, *args))
      end
    end
  end

  # Our text spinner class really doesn't like handling the TranslatedString or Untranslated classes returned
  # by the R18n library. So instead we return these TextWrapper instances which have dynamically defined methods
  # corresponding to the known structure of the R18n text file. Most importantly, if a user has accessed
  # a leaf node in the code we return a regular String instead of the R18n classes.
  class TextWrapper
    def initialize(translation_tree)
      @tree = translation_tree
      @tree.translation_keys.each do |k|
        # Integer keys are not translatable - they're quantity indicators in the key that
        # are instead sent as arguments. If we see one here, it means it was not correctly
        # labeled as plural with !!pl in the parent key
        if k.class == Integer
          raise MissingPlural.new(@tree.instance_variable_get(:@path), k)
        end
        k = k.to_sym
        define_singleton_method k do |*args|
          subtree = @tree.send(k, *args)
          if subtree.translation_keys.empty?
            # If there are no more possible children, just return the translated value
            subtree.to_s
          else
            TextWrapper.new(subtree)
          end
        end
      end
    end

    def method_missing(name, *args)
      raise InvalidKey.new(@tree.instance_variable_get(:@path), name)
    end

    class TextError < RuntimeError
      attr_accessor :line
      def set_call_context
        @line = caller(8, 1).first
        if @line =~ /.*\/lib\/(.*\.rb):(\d+)/
          @line = "File: #{$1} Line: #{$2}"
        end
      end
    end

    class InvalidKey < TextError
      def initialize(path, terminus)
        set_call_context
        # Calling back into Text here seems icky, this is an error
        # that only engineering should see.
        message = "i18n key #{path}.#{terminus} does not exist.\n"
        message << "Referenced from #{line}"
        super(message)
      end
    end

    class MissingPlural < TextError
      def initialize(path, terminus)
        set_call_context
        # Calling back into Text here seems icky, this is an error
        # that only engineering should see.
        message = "i18n key #{path}.#{terminus} appears to reference a pluralization.\n"
        message << "Please append the plural indicator '!!pl' to the end of #{path}.\n"
        message << "Referenced from #{line}"
        super(message)
      end
    end

  end
end
