# SpaceLens

SpaceLens is a lightweight macOS disk space analyzer built with SwiftUI.  
It provides a clear interactive sunburst diagram and a structured list to explore disk usage efficiently.

---

## Features

- **Sunburst visualization**  
  Interactive and zoomable. Hover to preview items, click to navigate into subfolders.

- **Folder scanning**  
  Scan any folder, volume, or the entire disk (with Full Disk Access enabled).

- **Contextual actions**  
  Right-click on any item to open it in Finder or copy its file path.

- **Customizable heatmaps**  
  Two modes:
  - By size
  - By file type (color-coded: PDF, media, code, archives, etc.)

- **Breadcrumb navigation**  
  Navigate back through folder hierarchies easily.

- **Progress indicator**  
  Shown during scanning and sunburst generation.

---

## Full Disk Access

To scan the entire disk, macOS requires granting SpaceLens **Full Disk Access**:

1. Open **System Settings → Privacy & Security → Full Disk Access**  
2. Add **SpaceLens.app** to the list  
3. Enable the toggle  
4. Restart the application

Without Full Disk Access, some system or user-protected folders will remain inaccessible due to macOS security layers such as SIP, TCC, or APFS snapshots.  
Even with Full Disk Access, certain locations (for example, `/System`, Mail, or Time Machine snapshots) may remain restricted. This is expected behavior on modern macOS versions.

---

## Known Limitations

- Some protected folders remain inaccessible despite Full Disk Access.  
- A relaunch of the signed application may be required after enabling Full Disk Access.  
- Scanning very large directory trees with many small files can take time.

---

## Technical Notes

- Built with **SwiftUI** for macOS 14 and later.  
- Uses **FileManager** for recursive scanning.  
- The sunburst view is rendered using **Canvas** for performance.  

---

## License

Released in 2025 by **Adrien Lor**.  
Distributed as free software for the community.  
See the [LICENSE](LICENSE) file for details.
