# adapted from http://snippets.dzone.com/posts/show/5811
class Hash
  # Replacing the to_yaml function so it'll serialize hashes sorted (by their keys)
  #
  # Original function is in /usr/lib/ruby/1.8/yaml/rubytypes.rb
  def to_yaml( opts = {} )
    YAML::quick_emit( object_id, opts ) do |out|
      out.map( taguri, to_yaml_style ) do |map|
        sort.each do |k, v|
          map.add( k, v )
        end
      end
    end
  end
end

# Preserve original encoding of characters.
# Must be loaded after Hash#to_yaml monkey patch
# so that it can be properly loaded
require 'yaml_waml'

namespace :i18n do
  desc 'Canonize i18n files (deep sort keys)'
  task :canonize_files, :only, :needs  => :environment do |t, args|
    targets = args[:only].is_a?(String) ? args[:only].split(':') : ['en', 'pt-BR']

    Dir['./config/locales/*'].each do |directory|
      targets.each do |basename|
        filename = File.join(directory, "#{basename}.yml")
        next unless File.exist?(filename)

        content = YAML.load(File.read(filename))
        next if content.empty?

        File.open(filename, 'w') do |f|
          f.write(content.to_yaml_with_decode)
        end

        content = File.read(filename)
        File.open(filename, 'w') do |f|
          f.write(content[5..-1].gsub(/\ *$/, ''))
        end
      end
    end
  end
end
