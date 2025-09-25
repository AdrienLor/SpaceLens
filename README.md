# SpaceLens

SpaceLens is a macOS application for visualizing disk usage.  
It allows you to explore a selected folder and quickly identify which files and subfolders consume the most space.

## Features
- Select any folder as the root of exploration.
- Hierarchical view of folders and files with size information.
- Progressive updates of folder sizes (with inline spinners while loading).
- Clear indication when access to a folder is denied.
- Breadcrumb navigation for moving through the folder hierarchy.
- In-memory cache to avoid unnecessary rescans.
- Sunburst visualisation with interactive navigation 

## Technology
- Swift 6
- SwiftUI
- Combine
- AppKit (for some macOS-specific components)
