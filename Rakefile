# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

task default: :test

desc "Run tests and enforce 100% line coverage for lib/ and bin/"
task :coverage do
  require "coverage"
  require "minitest"

  root = File.expand_path(__dir__)
  lib_dir = File.join(root, "lib")
  test_dir = File.join(root, "test")
  $LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)
  $LOAD_PATH.unshift(test_dir) unless $LOAD_PATH.include?(test_dir)

  ENV["XBOOKMARK_COVERAGE_RUNNER"] = "1"
  Coverage.start(lines: true)

  require "xbookmark"
  Dir[File.join(root, "lib/**/*.rb")].sort.each do |path|
    require path.delete_prefix("#{lib_dir}/").delete_suffix(".rb")
  end

  require "test_helper"
  Dir[File.join(test_dir, "**/*_test.rb")].sort.each { |path| require path }

  status = Minitest.run(["--seed", "1"])
  result = Coverage.result
  rows = XbookmarkCoverage.rows(result, root)
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

  abort "Minitest failed" unless status
  abort "Coverage is below 100%" unless covered == total
end

module XbookmarkCoverage
  module_function

  def rows(result, root)
    prefix = "#{root}/"
    result.each_with_object([]) do |(file, data), rows|
      next unless file.start_with?("#{prefix}lib/") || file.start_with?("#{prefix}bin/")

      row = row_for(file, data[:lines] || data, prefix)
      rows << row if row
    end
  end

  def row_for(file, lines, prefix)
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
    return nil if total.zero?

    { path: file.delete_prefix(prefix), covered: covered, total: total, missed: missed }
  end
end
