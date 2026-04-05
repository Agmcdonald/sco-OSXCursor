require 'xcodeproj'
project_path = "SCO-OSXCursor.xcodeproj"
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

dir = "SCO-OSXCursor/Views/Library"
file_path = "#{dir}/ComicInspectorView.swift"
group = project.main_group.find_subpath(dir, true)
group.set_source_tree('SOURCE_ROOT')
file_ref = group.new_reference("ComicInspectorView.swift")
target.add_file_references([file_ref])
project.save
