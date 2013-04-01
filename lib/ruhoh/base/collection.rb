module Ruhoh::Base
  class Collection

    attr_accessor :resource_name
    attr_reader :ruhoh

    def initialize(ruhoh)
      @ruhoh = ruhoh
    end

    def resource_name
      return @resource_name if @resource_name
      parts = self.class.name.split("::")
      parts.pop
      Ruhoh::Utils.underscore(parts.pop)
    end

    def namespace
      Ruhoh::Utils.underscore(resource_name)
    end

    # The default glob for finding files.
    # Every file in all child directories.
    def glob
      "**/*"
    end

    # Default paths to the 3 levels of the cascade.
    def paths
      a = [
        {
          "name" => "system",
          "path" => @ruhoh.paths.system
        }, 
        {
          "name" => "base",
          "path" => @ruhoh.paths.base
        }
      ]
      a << {
        "name" => "theme",
        "path" => @ruhoh.paths.theme
      } if @ruhoh.paths.theme

      a
    end

    # Does this resource have any valid paths to process?
    # A valid path may exist on any of the cascade levels.
    # False means there are no directories on any cascade level.
    # @returns[Boolean]
    def paths?
      !!Array(paths.map{ |h| h["path"] }).find do |path|
        File.directory?(File.join(path, namespace))
      end
    end

    def get(pointer)
      generate[pointer['id']]
    end

    def find(pointer)
      load_model(pointer)
    end

    def config
      config = @ruhoh.config[resource_name] || {}
      unless config.is_a?(Hash)
        Ruhoh.log.error("'#{resource_name}' config key in config.yml is a #{config.class}; it needs to be a Hash (object).")
      end
      config
    end

    # Generate all data resources for this data endpoint.
    #
    # id - (Optional) String or Array.
    #   Generate a single data resource at id.
    # block - (Optional) block.
    #   Implement custom validation logic by passing in a block. The block is given (id, self) as args.
    #   Return true/false for whether the file is valid/invalid.
    #   Example:
    #     Generate only files startng with the letter "a" :
    #     generate {|id| id.start_with?("a") }
    #
    # @returns[Hash(dict)] dictionary of data hashes {"id" => {<data>}}
    def generate(id=nil, &block)
      dict = {}
      files(id, &block).each { |pointer|
        pointer["resource"] = resource_name
        result = if model?
          load_model(pointer).generate
        else
          {
            pointer['id'] => pointer
          }
        end
        dict.merge!(result)
      }
      Ruhoh::Utils.report(self.resource_name, dict, [])
      dict
    end

    # Collect all files (as mapped by data resources) for this data endpoint.
    # Each resource can have 3 file references, one per each cascade level.
    # The file hashes are collected in order 
    # so they will overwrite eachother if found.
    # Returns Array of file data hashes.
    # 
    # id - (Optional) String or Array.
    #   Collect all files for a single data resource.
    #   Can be many files due to the cascade.
    # block - (Optional) block.
    #   Implement custom validation logic by passing in a block. The block is given (id, self) as args.
    #   Return true/false for whether the file is valid/invalid.
    #   Note it is preferred to pass the block to #generate as #files is a low-level method.
    #
    # Returns Array of file hashes.
    def files(id=nil, &block)
      a = []
      Array(self.paths.map{|h| h["path"]}).each do |path|
        namespaced_path = File.join(path, namespace)
        next unless File.directory?(namespaced_path)
        FileUtils.cd(namespaced_path) {
          file_array = (id ? Array(id) : Dir[self.glob])
          file_array.each { |id|

            next unless(block_given? ? yield(id, self) : valid_file?(id))

            a << {
              "id" => id,
              "realpath" => File.realpath(id),
              "resource" => resource_name,
            }
          }
        }
      end
      a
    end

    def valid_file?(filepath)
      return false unless File.exist? filepath
      return false if FileTest.directory?(filepath)
      return false if filepath.start_with?('.')
      excludes = Array(config['exclude']).map { |node| Regexp.new(node) }
      excludes.each { |regex| return false if filepath =~ regex }
      true
    end

    %w{
      collection_view
      model
      model_view
      client
      compiler
      watcher
      previewer
    }.each do |method_name|
      define_method(method_name) do
        get_module_namespace.const_get(camelize(method_name).to_sym)
      end

      define_method("#{method_name}?") do
        get_module_namespace.const_defined?(camelize(method_name).to_sym)
      end
    end

    def load_collection_view
      @_collection_view ||= collection_view? ?
                              collection_view.new(self) :
                              Ruhoh::Base::CollectionView.new(self)
    end

    def load_model(opts)
      model.new(@ruhoh, opts)
    end

    def load_model_view(opts)
      model_view.new(@ruhoh, opts)
    end

    def load_client(opts)
      @_client ||= client.new(load_collection_view, opts)
    end

    def load_compiler
      @_compiler ||= compiler.new(load_collection_view)
    end

    def load_watcher(*args)
      @_watcher ||= watcher.new(load_collection_view)
    end

    def load_previewer(*args)
      @_previewer ||= previewer.new(@ruhoh)
    end

    protected

    # Load the registered resource else default to Pages if not configured.
    # @returns[Constant] the resource's module namespace
    def get_module_namespace
      type = @ruhoh.config[resource_name]["use"] rescue nil
      if type
        if @ruhoh.resources.registered.include?(type)
          Ruhoh::Resources.const_get(camelize(type))
        elsif @ruhoh.resources.base.include?(type)
          Ruhoh::Base.const_get(camelize(type))
        else
          klass = camelize(type)
          Friend.say {
            red "#{resource_name} resource set to use:'#{type}' in config.yml but Ruhoh::Resources::#{klass} does not exist."
          }
          abort
        end
      else
        if @ruhoh.resources.registered.include?(resource_name)
          Ruhoh::Resources.const_get(camelize(resource_name))
        else
          Ruhoh::Base.const_get(:Pages)
        end
      end
    end

    def camelize(name)
      self.class.camelize(name)
    end

    def self.camelize(name)
      name.to_s.split('_').map {|a| a.capitalize}.join
    end
  end
end