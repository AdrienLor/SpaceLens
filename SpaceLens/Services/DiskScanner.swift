import Foundation

struct DiskScanner {
    /// Lance un scan progressif d'un dossier
    static func scanFolderProgressive(
        at url: URL,
        onNode: @escaping (Node) -> Void,
        onUpdate: @escaping (Node) -> Void
    ) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for item in contents {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)

            let attrs = try? fm.attributesOfItem(atPath: item.path)
            let size = (!isDir.boolValue ? (attrs?[.size] as? Int64) ?? 0 : 0)
            let modified = (attrs?[.modificationDate] as? Date)

            var node = Node(
                url: item,
                name: item.lastPathComponent,
                size: size,
                isDir: isDir.boolValue,
                modified: modified
            )
            if isDir.boolValue {
                node.isLoading = true
            }

            // Publier immédiatement (fichier avec sa vraie taille, dossier avec 0 = "en cours")
            onNode(node)

            // Si c’est un dossier → calculer sa vraie taille en arrière-plan
            if isDir.boolValue {
                // Removed initial onUpdate(node) in loading state, as onNode already does this.

                DispatchQueue.global(qos: .utility).async {
                    let result = tryComputeFolderSize(at: item)
                    var final = node
                    if result.accessDenied {
                        final.size = 0
                        final.accessDenied = true
                        final.isLoading = false
                    } else {
                        final.size = result.size
                        final.accessDenied = false
                        final.isLoading = false
                    }
                    // Update cached value to ensure isLoading does not remain true
                    // This guarantees that spinners don't reappear when reopening a folder from the breadcrumb.
                    // Assuming there is a cache or data structure to update, update it here.
                    // Example: Cache.shared.updateNode(final)
                    
                    DispatchQueue.main.async {
                        onUpdate(final)
                    }
                }
            }
        }
    }

    static func tryComputeFolderSize(at url: URL) -> (size: Int64, accessDenied: Bool) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else {
            return (0, true) // impossible d’énumérer → probablement accès refusé
        }
        var total: Int64 = 0
        var foundSomething = false
        for case let u as URL in en {
            if let s = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int64) {
                total += s
                foundSomething = true
            }
        }
        if !foundSomething {
            // Rien de lisible → probablement accès refusé
            return (0, true)
        }
        return (total, false)
    }
    
    /// Récursion pour calculer la vraie taille d'un dossier
    static func computeFolderSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let fileSize = attrs[.size] as? Int64 {
                total += fileSize
            }
        }
        return total
    }
}

extension DiskScanner {
    /// Scan récursif jusqu'à une profondeur donnée (pour Sunburst)
    static func scanFolderHierarchy(
        at url: URL,
        maxDepth: Int = 8
    ) -> Node {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let size = (!isDir.boolValue ? (attrs?[.size] as? Int64) ?? 0 : 0)
        let modified = (attrs?[.modificationDate] as? Date)

        var node = Node(
            url: url,
            name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent,
            size: size,
            isDir: isDir.boolValue,
            modified: modified
        )

        if isDir.boolValue {
            if maxDepth > 0 {
                do {
                    let contents = try fm.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )

                    var children: [Node] = []
                    for item in contents {
                        let child = scanFolderHierarchy(at: item, maxDepth: maxDepth - 1)
                        children.append(child)
                    }

                    // Calculer taille du dossier = somme enfants si non vide
                    if !children.isEmpty {
                        node.size = children.map(\.size).reduce(0, +)
                        node.children = children
                    }
                } catch {
                    node.size = 0
                    node.accessDenied = true
                }
                return node
            } else {
                // depth limit reached: compute accurate deep size
                node.size = deepFolderSize(at: url)
                return node
            }
        } else {
            return node
        }
    }
}

extension DiskScanner {
    static func deepFolderSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey]
        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                do {
                    let rv = try fileURL.resourceValues(forKeys: Set(keys))
                    if rv.isRegularFile == true {
                        if let alloc = rv.fileAllocatedSize { total += Int64(alloc) }
                        else {
                            let attrs = try fm.attributesOfItem(atPath: fileURL.path)
                            if let s = attrs[.size] as? NSNumber { total += s.int64Value }
                        }
                    }
                } catch { continue }
            }
        }
        return total
    }
}
