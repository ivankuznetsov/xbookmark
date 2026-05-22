# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc "Run specs and enforce 100% line coverage for lib/ and bin/"
task :coverage do
  require "coverage"
  require "rspec/core"

  root = File.expand_path(__dir__)
  lib_dir = File.join(root, "lib")
  $LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

  Coverage.start(lines: true)

  require "xbookmark"
  Dir[File.join(root, "lib/**/*.rb")].sort.each do |path|
    require path.delete_prefix("#{lib_dir}/").delete_suffix(".rb")
  end

  status = RSpec::Core::Runner.run(["--format", "progress", "spec"])
  result = Coverage.result
  rows = coverage_rows(result, root)
  covered = rows.sum { |row| row[:covered] }
  total = rows.sum { |row| row[:total] }

  puts
  puts format("Coverage: %.2f%% (%d/%d)", (100.0 * covered / total), covered, total)
  rows.sort_by { |row| [row[:covered] == row[:total] ? 1 : 0, row[:path]] }.each do |row|
    puts format("%6.2f%% %4d/%-4d %s missed:%s",
                (100.0 * row[:covered] / row[:total]),
                row[:covered],
                row[:total],
                row[:path],
                row[:missed].join(","))
  end

  abort "RSpec failed" unless status.zero?
  abort "Coverage is below 100%" unless covered == total
end

def coverage_rows(result, root)
  prefix = "#{root}/"
  result.each_with_object([]) do |(file, data), rows|
    next unless file.start_with?("#{prefix}lib/") || file.start_with?("#{prefix}bin/")

    lines = data[:lines] || data
    covered = 0
    total = 0
    missed = []
    lines.each_with_index do |count, index|
      next if count.nil?

      total += 1
      if count.positive?
        covered += 1
      else
        missed << index + 1
      end
    end
    next if total.zero?

    rows << { path: file.delete_prefix(prefix), covered: covered, total: total, missed: missed }
  end
end
