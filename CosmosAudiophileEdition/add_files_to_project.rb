#!/usr/bin/env ruby
# add_files_to_project.rb — Cosmos Audiophile Edition
#
# Automatically adds all Swift files from CosmosAudiophileEdition/
# into the Xcode project so you never have to open Xcode on Windows.
#
# Run by GitHub Actions (Step 3), but you can also run it manually
# on any Mac with: ruby add_files_to_project.rb

require 'xcodeproj'
require 'pathname'

# ── Find the Xcode project ──────────────────────────────────────────────────
project_path = Dir.glob('*.xcodeproj').first ||
               Dir.glob('*/*.xcodeproj').reject { |p| p.include?('DerivedData') }.first

abort "❌  No .xcodeproj found. Make sure you run this from the repo root." unless project_path

puts "📂  Project : #{project_path}"
project     = Xcodeproj::Project.open(project_path)
project_dir = Pathname.new(File.expand_path(File.dirname(project_path)))

# ── Find the main app target (not test, not extension) ─────────────────────
target = project.targets.find { |t|
  t.product_type == 'com.apple.product-type.application'
} || project.targets.first

abort "❌  No app target found in #{project_path}" unless target
puts "🎯  Target  : #{target.name}"

# ── Locate the new files directory ─────────────────────────────────────────
new_dir = Pathname.new(File.expand_path('CosmosAudiophileEdition'))
abort "❌  CosmosAudiophileEdition/ folder not found. Is it in the repo root?" unless new_dir.exist?

# ── Helper: find or create a PBX group ─────────────────────────────────────
def find_or_create_group(parent, name, path_hint = nil)
  existing = parent.children.find do |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) &&
    (c.name == name || c.display_name == name)
  end
  return existing if existing
  parent.new_group(name, path_hint || name)
end

# ── Create or reuse top-level group ────────────────────────────────────────
ae_group = find_or_create_group(
  project.main_group,
  'CosmosAudiophileEdition',
  new_dir.relative_path_from(project_dir).to_s
)

# ── Walk every Swift file under CosmosAudiophileEdition/ ───────────────────
swift_files = Dir.glob('CosmosAudiophileEdition/**/*.swift').sort
puts "🔍  Found #{swift_files.count} Swift files to add\n\n"

files_added  = 0
files_skipped = 0

swift_files.each do |rel_path|
  abs_path = Pathname.new(File.expand_path(rel_path))

  # Skip if already referenced in the project
  already_in_project = project.files.any? do |f|
    begin
      f.real_path == abs_path
    rescue
      false
    end
  end

  if already_in_project
    puts "  ⏭   Skip (already in project): #{rel_path}"
    files_skipped += 1
    next
  end

  # Build group hierarchy:
  #   "CosmosAudiophileEdition/Views/Player/Foo.swift"
  #   → parts = ["Views", "Player"]
  parts        = Pathname.new(rel_path).each_filename.to_a
  group_parts  = parts[1..-2]   # drop leading 'CosmosAudiophileEdition' and filename
  file_name    = parts.last

  current_group = ae_group
  group_parts.each do |part|
    current_group = find_or_create_group(current_group, part)
  end

  # Add file reference
  file_ref = current_group.new_file(abs_path.to_s)

  # Add to target's Compile Sources phase
  unless target.source_build_phase.files_references.include?(file_ref)
    target.source_build_phase.add_file_reference(file_ref)
  end

  puts "  ✅  Added: #{rel_path}"
  files_added += 1
end

puts "\n#{'-' * 60}"
puts "✅  Added   : #{files_added} files"
puts "⏭   Skipped : #{files_skipped} files (already present)"
puts "#{'-' * 60}"

project.save
puts "💾  Project saved → #{project_path}"
