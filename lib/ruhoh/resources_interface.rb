module Ruhoh::Resources ; end
# Require all the resources
FileUtils.cd(File.join(File.dirname(__FILE__), 'base')) do
  Dir['*.rb'].each do |f|
    require File.join(File.dirname(__FILE__), 'base', f)
  end
  Dir[File.join('*', '*.rb')].each do |f|
    require File.join(File.dirname(__FILE__), 'base', f)
  end
end
FileUtils.cd(File.join(File.dirname(__FILE__), 'resources')) do
  Dir[File.join('**', '*.rb')].each do |f|
    require File.join(File.dirname(__FILE__), 'resources', f)
  end
end

class Ruhoh
  class ResourcesInterface
    Whitelist = %w{
      collection
    }

    def collection(resource)
      get_module_namespace_for(resource).const_get(:Collection)
    end

    def collection?(resource)
      get_module_namespace_for(resource).const_defined?(:Collection)
    end

    def method_missing(name, *args, &block)
      resource = name.to_s.gsub(/^load_/, '')
      if Whitelist.include?(resource)
        load_class_instance_for(resource, *args)
      else
        super
      end
    end

    def respond_to?(method)
      resource = method.gsub(/^load_/, '')
      return true if Whitelist.include?(resource)
      super
    end


    def initialize(ruhoh)
      @ruhoh = ruhoh
    end

    def all
      a = (discover + registered).uniq
      a.delete("compiled")
      a
    end

    def base
      Ruhoh::Base.constants.select{ |a|
        Ruhoh::Base.const_get(a).class == Module
      }.map{ |a| 
        a.to_s.downcase
      }
    end 

    def registered
      Ruhoh::Resources.constants.map{ |a| a.to_s.downcase }
    end

    # discover all the resource mappings
    def discover
      return FileUtils.cd(@ruhoh.base) {
        return Dir['*'].select { |x| 
          File.directory?(x) && !["plugins"].include?(x)
        }
      }
    end

    def acting_as_pages
      r = registered.dup # registered non-pages
      r.delete("pages")
      r.delete("posts")

      pages = @ruhoh.config.map do |resource, config|
        next if resource == "theme"
        next if (config && config["use"] && config["use"] != "pages")
        next if r.include?(resource)
        next unless discover.include?(resource)
        resource
      end.compact

      pages
    end

    def non_pages
      a = (discover + registered) - acting_as_pages 
      a.delete("theme")
      a.delete("compiled") # TODO: remove user-defined compiled folder.
      a
    end

    def exists?(name)
      all.include?(name)
    end
    alias_method :exist?, :exists?

    protected

    # Load and cache a given resource collection.
    # This allows you to work with single object instance and perform
    # persistant mutations on it if necessary.
    # @returns[Class Instance] of the resource and class_name given.
    def load_class_instance_for(class_name, *args)
      resource, opts = *args

      var = "@#{resource}_#{class_name}"
      if instance_variable_defined?(var) && instance_variable_get(var)
        instance_variable_get(var)
      else
        klass = get_module_namespace_for(resource)
        instance = if klass.const_defined?(camelize(class_name))
          klass.const_get(camelize(class_name)).new(@ruhoh)
        else
          Ruhoh::Base::Collection.new(@ruhoh)
        end
        instance.resource_name = resource
        instance_variable_set(var, instance)
        instance
      end
    end

    # Load the registered resource else default to Pages if not configured.
    # @returns[Constant] the resource's module namespace
    def get_module_namespace_for(resource)
      type = @ruhoh.config[resource]["use"] rescue nil
      if type
        if registered.include?(type)
          Ruhoh::Resources.const_get(camelize(type))
        elsif base.include?(type)
          Ruhoh::Base.const_get(camelize(type))
        else
          klass = camelize(type)
          Friend.say {
            red "#{resource} resource set to use:'#{type}' in config.yml but Ruhoh::Resources::#{klass} does not exist."
          }
          abort
        end
      else
        if registered.include?(resource)
          Ruhoh::Resources.const_get(camelize(resource))
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