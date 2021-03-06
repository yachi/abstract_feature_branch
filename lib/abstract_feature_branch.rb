require 'rubygems'
require 'bundler'
require 'yaml'
YAML::ENGINE.yamler = "syck" if RUBY_VERSION.start_with?('1.9')
begin
  Bundler.setup(:default)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'logger' unless defined?(Rails) && Rails.logger
require 'deep_merge' unless {}.respond_to?(:deep_merge!)

require File.join(File.dirname(__FILE__), 'abstract_feature_branch', 'configuration')

module AbstractFeatureBranch
  ENV_FEATURE_PREFIX = "abstract_feature_branch_"

  class << self
    extend Forwardable
    def_delegators :configuration, :application_root, :application_root=, :initialize_application_root, :application_environment, :application_environment=, :initialize_application_environment, :logger, :logger=, :initialize_logger, :cacheable, :cacheable=, :initialize_cacheable, :user_features_storage, :user_features_storage=, :initialize_user_features_storage

    def configuration
      @configuration ||= Configuration.new
    end

    def environment_variable_overrides
      @environment_variable_overrides ||= load_environment_variable_overrides
    end
    def load_environment_variable_overrides
      @environment_variable_overrides = featureize_keys(select_feature_keys(booleanize_values(downcase_keys(ENV))))
    end
    def local_features
      @local_features ||= load_local_features
    end
    def load_local_features
      @local_features = {}
      load_specific_features(@local_features, '.local.yml')
    end
    def features
      @features ||= load_features
    end
    def load_features
      @features = {}
      load_specific_features(@features, '.yml')
    end
    # performance optimization via caching of feature values resolved through environment variable overrides and local features
    def environment_features(environment)
      @environment_features ||= {}
      @environment_features[environment] ||= load_environment_features(environment)
    end
    def load_environment_features(environment)
      @environment_features ||= {}
      features[environment] ||= {}
      local_features[environment] ||= {}
      @environment_features[environment] = features[environment].merge(local_features[environment]).merge(environment_variable_overrides)
    end
    def application_features
      unload_application_features unless cacheable?
      environment_features(application_environment)
    end
    def load_application_features
      AbstractFeatureBranch.load_environment_variable_overrides
      AbstractFeatureBranch.load_features
      AbstractFeatureBranch.load_local_features
      AbstractFeatureBranch.load_environment_features(application_environment)
    end
    def unload_application_features
      @environment_variable_overrides = nil
      @features = nil
      @local_features = nil
      @environment_features = nil
    end
    def cacheable?
      value = downcase_keys(cacheable)[application_environment]
      value = (application_environment != 'development') if value.nil?
      value
    end
    def toggle_features_for_user(user_id, features)
      features.each do |name, value|
        if value
          user_features_storage.sadd("#{ENV_FEATURE_PREFIX}#{name.to_s.downcase}", user_id)
        else
          user_features_storage.srem("#{ENV_FEATURE_PREFIX}#{name.to_s.downcase}", user_id)
        end
      end
    end

    private

    def load_specific_features(features_hash, extension)
      Dir.glob(File.join(application_root, 'config', 'features', '**', "*#{extension}")).each do |feature_configuration_file|
        features_hash.deep_merge!(downcase_feature_hash_keys(YAML.load_file(feature_configuration_file)))
      end
      main_local_features_file = File.join(application_root, 'config', "features#{extension}")
      features_hash.deep_merge!(downcase_feature_hash_keys(YAML.load_file(main_local_features_file))) if File.exists?(main_local_features_file)
      features_hash
    end

    def featureize_keys(hash)
      Hash[hash.map {|k, v| [k.sub(ENV_FEATURE_PREFIX, ''), v]}]
    end

    def select_feature_keys(hash)
      hash.reject {|k, v| !k.start_with?(ENV_FEATURE_PREFIX)} # using reject for Ruby 1.8 compatibility as select returns an array in it
    end

    def booleanize_values(hash)
      hash_values = hash.map do |k, v|
        normalized_value = v.to_s.downcase
        boolean_value = normalized_value == 'true'
        new_value = normalized_value == 'per_user' ? 'per_user' : boolean_value
        [k, new_value]
      end
      Hash[hash_values]
    end

    def downcase_keys(hash)
      Hash[hash.map {|k, v| [k.to_s.downcase, v]}]
    end

    def downcase_feature_hash_keys(hash)
      Hash[(hash || {}).map {|k, v| [k, v && downcase_keys(v)]}]
    end
  end
end

require File.join(File.dirname(__FILE__), 'ext', 'feature_branch')
require File.join(File.dirname(__FILE__), 'abstract_feature_branch', 'file_beautifier')
