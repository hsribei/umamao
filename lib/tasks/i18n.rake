require 'active_support'

def convert_hash_to_ordered_hash_and_sort(object, deep = false)
  # from http://seb.box.re/2010/1/15/deep-hash-ordering-with-ruby-1-8/
  if object.is_a?(Hash)
    # Hash is ordered in Ruby 1.9!
    res = (RUBY_VERSION >= '1.9' ? Hash.new : ActiveSupport::OrderedHash.new).tap do |map|
      object.each {|k, v| map[k] = deep ? convert_hash_to_ordered_hash_and_sort(v, deep) : v }
    end
    return res.class[res.sort {|a, b| a[0].to_s <=> b[0].to_s } ]
  elsif deep && object.is_a?(Array)
    array = Array.new
    object.each_with_index {|v, i| array[i] = convert_hash_to_ordered_hash_and_sort(v, deep) }
    return array
  else
    return object
  end
end

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
          f.write(convert_hash_to_ordered_hash_and_sort(content, true))
        end
      end
    end
  end
end
